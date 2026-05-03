//
//  SpacetimeDBClient+receiveMessage.swift
//  spacetimedb-swift-sdk
//
//  v2 ServerMessage dispatcher.
//
//  Wire framing per ServerMessage:
//    [u8 compression_tag] [BSATN body]
//      compression_tag: 0=None, 1=Brotli, 2=Gzip
//
//  After optional decompression the body begins with the ServerMessage
//  variant tag (Tags.ServerMessage), followed by the variant payload.
//

import Foundation
import BSATN

extension SpacetimeDBClient {
    internal func receiveMessage() async throws {
        guard let webSocketTask else { return }

        while !Task.isCancelled {
            let message = try await webSocketTask.receive()
            switch message {
            case .data(let data):
                await processOrForwardMessage(data)
            case .string(let string):
                if let data = string.data(using: .utf8) {
                    await processOrForwardMessage(data)
                }
            @unknown default:
                break
            }
        }
    }

    private func processOrForwardMessage(_ data: Data) async {
        await ClientMetrics.shared.recordReceived(db: dbName, byteCount: data.count)
        if debugEnabled {
            print("=== Received BSATN Message (\(data.count) bytes) ===")
            printHexData(data)
            print("==============================")
        }
        await clientDelegate?.onIncomingMessage(client: self, message: data)

        var reader = BSATNReader(data: data, debugEnabled: debugEnabled)
        let compressionTag: UInt8
        do {
            compressionTag = try reader.read()
        } catch {
            debugLog(">>> Error reading compression tag: \(error)")
            return
        }

        if compressionTag != BSATN.Compression.none.rawValue {
            let compressedBody = reader.remainingData()
            do {
                let decompressed: Data
                if compressionTag == BSATN.Compression.brotli.rawValue {
                    decompressed = try MessageDecompression.brotli(compressedBody)
                } else if compressionTag == BSATN.Compression.gzip.rawValue {
                    decompressed = try MessageDecompression.gzip(compressedBody)
                } else {
                    debugLog(">>> Unknown compression tag: \(compressionTag)")
                    return
                }
                reader = BSATNReader(data: decompressed, debugEnabled: debugEnabled)
            } catch {
                debugLog(">>> Decompression failed: \(error)")
                return
            }
        }

        let messageTag: UInt8
        do {
            messageTag = try reader.read()
        } catch {
            debugLog(">>> Error reading message tag: \(error)")
            return
        }

        do {
            switch messageTag {
            case Tags.ServerMessage.initialConnection.rawValue:
                try await handleInitialConnection(reader: reader)
            case Tags.ServerMessage.subscribeApplied.rawValue:
                try await handleSubscribeApplied(reader: reader)
            case Tags.ServerMessage.unsubscribeApplied.rawValue:
                try await handleUnsubscribeApplied(reader: reader)
            case Tags.ServerMessage.subscriptionError.rawValue:
                try await handleSubscriptionError(reader: reader)
            case Tags.ServerMessage.transactionUpdate.rawValue:
                try await handleTransactionUpdate(reader: reader)
            case Tags.ServerMessage.oneOffQueryResult.rawValue:
                try await handleOneOffQueryResult(reader: reader)
            case Tags.ServerMessage.reducerResult.rawValue:
                try await handleReducerResult(reader: reader)
            case Tags.ServerMessage.procedureResult.rawValue:
                try await handleProcedureResult(reader: reader)
            default:
                debugLog(">>> Unknown server message tag: \(messageTag)")
            }
        } catch {
            debugLog(">>> Failed to decode message tag \(messageTag): \(error)")
        }
    }

    // MARK: - Per-message handlers

    private func handleInitialConnection(reader: BSATNReader) async throws {
        let msg = try InitialConnectionMessage(reader: reader)
        currentIdentity = msg.identity
        currentConnectionId = ConnectionId(msg.connectionId)
        lastToken = AuthenticationToken(rawValue: msg.token)
        reconnectAttempts = 0
        await clientDelegate?.onIdentityReceived(client: self, token: msg.token, identity: msg.identity)
        emit(connection: .connected(
            identity: Identity(msg.identity),
            connectionId: ConnectionId(msg.connectionId),
            token: msg.token
        ))
    }

    private func handleSubscribeApplied(reader: BSATNReader) async throws {
        let msg = try SubscribeAppliedMessage(reader: reader)
        let queryId = msg.querySetId.id
        await dispatchInitialRows(msg.rows)
        await clientDelegate?.onSubscribeApplied(client: self, queryId: queryId)
        emit(subscription: .applied(queryId: queryId))
        resolveSubscriptionApplied(queryId: queryId)
    }

    private func handleUnsubscribeApplied(reader: BSATNReader) async throws {
        let msg = try UnsubscribeAppliedMessage(reader: reader)
        let queryId = msg.querySetId.id
        if let dropped = msg.droppedRows {
            // Server echoed the rows being removed (SendDroppedRows flag).
            // Surface as deletes on the per-table streams so observers can
            // invalidate their caches.
            await dispatchDroppedRows(dropped)
        }
        await clientDelegate?.onUnsubscribeApplied(client: self, queryId: queryId)
        emit(subscription: .unsubscribed(queryId: queryId))
        resolveSubscriptionUnsubscribed(queryId: queryId)
    }

    private func handleSubscriptionError(reader: BSATNReader) async throws {
        let msg = try SubscriptionErrorMessage(reader: reader)
        let queryId = msg.querySetId.id
        await clientDelegate?.onSubscriptionError(
            client: self,
            queryId: queryId,
            requestId: msg.requestId,
            error: msg.error
        )
        emit(subscription: .error(queryId: queryId, requestId: msg.requestId, message: msg.error))
        failSubscriptionFutures(queryId: queryId, message: msg.error)
    }

    private func handleTransactionUpdate(reader: BSATNReader) async throws {
        let update = try TransactionUpdate(reader: reader)
        await dispatchTransactionUpdate(update)
    }

    private func handleOneOffQueryResult(reader: BSATNReader) async throws {
        let msg = try OneOffQueryResultMessage(reader: reader)
        resolveOneOffQuery(msg)
    }

    private func handleReducerResult(reader: BSATNReader) async throws {
        let msg = try ReducerResultMessage(reader: reader)
        let reducerName = self.reducerName(forRequestId: msg.requestId) ?? "<unknown>"
        let timestamp = Date(timeIntervalSince1970: TimeInterval(msg.timestampNanos) / 1_000_000_000)

        // Dispatch table updates BEFORE resolving the caller's continuation
        // so observers see the row diffs at least as early as the caller
        // sees the success return value.
        if case .ok(_, let txUpdate) = msg.outcome {
            await dispatchTransactionUpdate(txUpdate)
        }

        emit(reducer: ReducerEvent(
            requestId: msg.requestId,
            reducerName: reducerName,
            timestamp: timestamp,
            outcome: msg.outcome
        ))
        await clientDelegate?.onReducerResponse(
            client: self,
            requestId: msg.requestId,
            reducerName: reducerName,
            outcome: msg.outcome
        )
        resolvePendingReducer(
            requestId: msg.requestId,
            timestampNanos: msg.timestampNanos,
            outcome: msg.outcome
        )
    }

    private func handleProcedureResult(reader: BSATNReader) async throws {
        let msg = try ProcedureResultMessage(reader: reader)
        let procedureName = self.procedureName(forRequestId: msg.requestId) ?? "<unknown>"
        await clientDelegate?.onProcedureResponse(
            client: self,
            requestId: msg.requestId,
            procedureName: procedureName,
            status: msg.status
        )
        resolvePendingProcedure(requestId: msg.requestId, status: msg.status)
    }

    // MARK: - Row dispatch helpers

    /// Decode and emit the snapshot rows from `SubscribeApplied.rows`.
    /// All rows are surfaced as inserts (it's the initial state).
    private func dispatchInitialRows(_ rows: QueryRows) async {
        for table in rows.tables {
            let inserts = decodeRows(table.rows.rows, tableName: table.tableName)
            if inserts.isEmpty { continue }
            await emitTableUpdate(tableName: table.tableName, deletes: [], inserts: inserts)
        }
    }

    /// Decode and emit the dropped-row payload from `UnsubscribeApplied.rows`
    /// (only present when SendDroppedRows was requested). All rows are
    /// surfaced as deletes.
    private func dispatchDroppedRows(_ rows: QueryRows) async {
        for table in rows.tables {
            let deletes = decodeRows(table.rows.rows, tableName: table.tableName)
            if deletes.isEmpty { continue }
            await emitTableUpdate(tableName: table.tableName, deletes: deletes, inserts: [])
        }
    }

    /// Decode and emit row diffs from a `TransactionUpdate`, batching
    /// per (tableName) across all query sets and TableUpdateRows variants.
    private func dispatchTransactionUpdate(_ update: TransactionUpdate) async {
        // Collapse all per-(querySet, table, rows-variant) diffs into a
        // single (deletes, inserts) pair per table name. Event-table rows
        // are surfaced as inserts (they fire onInsert but aren't retained).
        var bucket: [String: (deletes: [Any], inserts: [Any])] = [:]

        for set in update.querySets {
            for table in set.tables {
                for rowSet in table.rows {
                    switch rowSet {
                    case .persistent(let inserts, let deletes):
                        let dec = decodeRows(deletes.rows, tableName: table.tableName)
                        let ins = decodeRows(inserts.rows, tableName: table.tableName)
                        if dec.isEmpty && ins.isEmpty { continue }
                        bucket[table.tableName, default: ([], [])].deletes.append(contentsOf: dec)
                        bucket[table.tableName, default: ([], [])].inserts.append(contentsOf: ins)
                    case .event(let events):
                        let ins = decodeRows(events.rows, tableName: table.tableName)
                        if ins.isEmpty { continue }
                        bucket[table.tableName, default: ([], [])].inserts.append(contentsOf: ins)
                    }
                }
            }
        }

        for (tableName, diff) in bucket {
            await emitTableUpdate(tableName: tableName, deletes: diff.deletes, inserts: diff.inserts)
        }
    }

    /// Fan out a single table's diff to the legacy delegate, the per-table
    /// stream, and the per-row stream (with PK-matched updates).
    private func emitTableUpdate(tableName: String, deletes: [Any], inserts: [Any]) async {
        let event = TableEvent(tableName: tableName, deletes: deletes, inserts: inserts)
        emit(tableEvent: event)
        await clientDelegate?.onTableUpdate(client: self, event: event)
    }

    /// Decode a flat array of BSATN-encoded rows for the named table.
    /// If no decoder is registered, returns the raw `Data` rows so the
    /// caller can still see the diff (legacy behaviour).
    private func decodeRows(_ rawRows: [Data], tableName: String) -> [Any] {
        guard !rawRows.isEmpty else { return [] }
        guard let decoder = decoder(forTable: tableName) else {
            debugLog(">>> No decoder registered for table: \(tableName); returning raw rows")
            return rawRows.filter { !$0.isEmpty }.map { $0 as Any }
        }
        var result: [Any] = []
        result.reserveCapacity(rawRows.count)
        for row in rawRows where !row.isEmpty {
            do {
                let r = BSATNReader(data: row, debugEnabled: debugEnabled)
                result.append(try decoder.decode(reader: r))
            } catch {
                debugLog(">>> Error decoding row from \(tableName): \(error)")
            }
        }
        return result
    }

    // MARK: - Hex dump

    private func printHexData(_ data: Data) {
        let bytes = Array(data)
        let bytesPerLine = 16
        let maxBytes = 16384
        let bytesToPrint = min(bytes.count, maxBytes)

        for i in stride(from: 0, to: bytesToPrint, by: bytesPerLine) {
            print(String(format: "0x%08X: ", i), terminator: "")
            for j in 0..<bytesPerLine {
                if i + j < bytes.count {
                    print(String(format: "%02X ", bytes[i + j]), terminator: "")
                } else {
                    print("   ", terminator: "")
                }
                if j == 7 && i + j < bytes.count {
                    print(" ", terminator: "")
                }
            }
            print(" |", terminator: "")
            for j in 0..<bytesPerLine {
                if i + j < bytes.count {
                    let byte = bytes[i + j]
                    print(byte >= 32 && byte <= 126 ? String(format: "%c", byte) : ".", terminator: "")
                } else {
                    print(" ", terminator: "")
                }
            }
            print("|")
        }
        if bytes.count > maxBytes {
            print("... (truncated, showing first \(maxBytes) of \(bytes.count) bytes)")
        }
        print(String(format: "Total bytes: %d (0x%X)", data.count, data.count))
    }
}
