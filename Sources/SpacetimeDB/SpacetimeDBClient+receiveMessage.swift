//
//  SpacetimeDBClient+receiveMessage.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation
import BSATN
import Compression

extension SpacetimeDBClient {
    internal func receiveMessage() async throws {
        guard let webSocketTask else {
            return
        }

    receiveNextMessage:
        while !Task.isCancelled {
            debugLog(">>> Waiting for WebSocket message...")
            let message = try await webSocketTask.receive()
            debugLog(">>> WebSocket message received")
            switch message {
            case .data(let data):
                debugLog(">>> Received binary data: \(data.count) bytes")
                await processOrForwardMessage(data)
            case .string(let string):
                debugLog(">>> Received string data: \(string.count) chars")
                guard let data = string.data(using: .utf8) else {
                    continue receiveNextMessage
                }
                await processOrForwardMessage(data)
            @unknown default:
                debugLog(">>> Received unknown message type")
                break
            }
        }
    }

    private func processOrForwardMessage(_ data: Data) async {
        debugLog(">>> processOrForwardMessage called with \(data.count) bytes")

        // Display hex representation of the data before processing
        if debugEnabled {
            print("=== Received BSATN Message ===")
            printHexData(data)
            print("==============================")
        }

        // Process the BSATN message
        debugLog(">>> Creating BSATNReader with \(data.count) bytes (first byte: 0x\(String(format: "%02X", data.first ?? 0)))")
        var reader = BSATNReader(data: data, debugEnabled: debugEnabled)

        // Read compression tag
        let compressionTag: UInt8
        do {
            compressionTag = try reader.read()
            debugLog(">>> Compression tag: \(compressionTag)")
        } catch {
            debugLog(">>> Error reading compression tag: \(error)")
            return
        }

        // Handle compression if needed
        if compressionTag != Tags.Compression.none.rawValue {
            debugLog(">>> Compressed message detected (compression: \(compressionTag))")

            // The rest of the data is compressed
            let compressedData = reader.remainingData()
            var decompressedData: Data?

            if compressionTag == Tags.Compression.brotli.rawValue {
                debugLog(">>> Decompressing Brotli message: \(compressedData.count) bytes")
                decompressedData = decompressBrotli(data: compressedData)
            } else if compressionTag == Tags.Compression.gzip.rawValue {
                debugLog(">>> Gzip compression is not currently supported")
                return
            }

            guard let decompressed = decompressedData else {
                debugLog(">>> Failed to decompress message")
                return
            }

            debugLog(">>> Decompressed to: \(decompressed.count) bytes")

            // Create a new reader with the decompressed data
            reader = BSATNReader(data: decompressed, debugEnabled: debugEnabled)
        }

        // Read message type tag
        let messageTag: UInt8 = (try? reader.read()) ?? 0
        debugLog(">>> Message type: \(messageTag)")

        do {
            if messageTag == Tags.ServerMessage.identityToken.rawValue {
                // Read IdentityTokenMessage
                let identityToken = try IdentityTokenMessage(modelValues: [
                    try reader.readAlgebraicValue(as: .uint256),
                    try reader.readAlgebraicValue(as: .string),
                    try reader.readAlgebraicValue(as: .uint128)
                ])
                debugLog(">>> Identity: \(identityToken)")

                // Store current identity
                self.currentIdentity = identityToken.identity
                await clientDelegate?.onIdentityReceived(client: self, token: identityToken.token, identity: identityToken.identity)
            } else if messageTag == Tags.ServerMessage.subscribeMultiApplied.rawValue {
                // Read SubscribeMultiApplied directly from reader
                let subscribeMultiApplied = try SubscribeMultiApplied(reader: reader)
                debugLog(">>> SubscribeMultiApplied: requestId=\(subscribeMultiApplied.requestId), tables=\(subscribeMultiApplied.update.tableUpdates.count)")

                for tableUpdate in subscribeMultiApplied.update.tableUpdates {
                    debugLog(">>> Table: \(tableUpdate.name) (id: \(tableUpdate.id), rows: \(tableUpdate.numRows))")

                    do {
                        let queryUpdate = try tableUpdate.getQueryUpdate()
                        debugLog(">>>   Deletes: \(queryUpdate.deletes.rows.count) rows")
                        debugLog(">>>   Inserts: \(queryUpdate.inserts.rows.count) rows")

                        let decoder = decoder(forTable: tableUpdate.name)
                        if let decoder {
                            // Process inserts
                            var insertedRows: [Any] = []
                            for (index, row) in queryUpdate.inserts.rows.enumerated() {
                                do {
                                    let reader = BSATNReader(data: row, debugEnabled: debugEnabled)
                                    let modelValue = try reader.readAlgebraicValue(as: .product(decoder.model))
                                    guard case .product(let values) = modelValue else { continue }
                                    let typedRow = try decoder.decode(modelValues: values)
                                    insertedRows.append(typedRow)
                                    debugLog(">>>     Row \(index) for \(tableUpdate.name): \(typedRow)")
                                } catch {
                                    debugLog(">>>     Error decoding row \(index): \(error)")
                                }
                            }

                            // Process deletes
                            var deletedRows: [Any] = []
                            for (index, row) in queryUpdate.deletes.rows.enumerated() {
                                // Skip empty row data
                                if row.isEmpty {
                                    continue
                                }
                                do {
                                    let reader = BSATNReader(data: row, debugEnabled: debugEnabled)
                                    let modelValue = try reader.readAlgebraicValue(as: .product(decoder.model))
                                    guard case .product(let values) = modelValue else { continue }
                                    let typedRow = try decoder.decode(modelValues: values)
                                    deletedRows.append(typedRow)
                                } catch {
                                    debugLog(">>>     Error decoding deleted row \(index): \(error)")
                                }
                            }

                            // Notify delegate
                            await clientDelegate?.onTableUpdate(
                                client: self,
                                table: tableUpdate.name,
                                deletes: deletedRows,
                                inserts: insertedRows
                            )
                        } else {
                            debugLog(">>>   No decoder registered for table: \(tableUpdate.name)")
                        }
                    } catch {
                        debugLog(">>>   Error parsing QueryUpdate: \(error)")
                    }
                }

                // Notify delegate
                clientDelegate?.onSubscribeMultiApplied(client: self, queryId: subscribeMultiApplied.queryId)
            } else if messageTag == Tags.ServerMessage.transactionUpdate.rawValue {
                // Read TransactionUpdate - pass the reader directly instead of remainingData
                debugLog(">>> Attempting to read TransactionUpdate from offset: \(reader.currentOffset)")

                // Create TransactionUpdate with the reader directly
                let update = try TransactionUpdate(reader: reader)

                // Check if this is from another user
                let isOwnUpdate = (update.callerIdentity.description == self.currentIdentity?.description)
                let updateSource = isOwnUpdate ? "OWN" : "OTHER USER"

                debugLog(">>> TransactionUpdate from \(updateSource):")
                debugLog(">>>   Reducer: \(update.reducerName)")
                debugLog(">>>   Caller: \(update.callerIdentity.description.prefix(16))...")
                debugLog(">>>   Request ID: \(update.reducerCall.requestId)")
                debugLog(">>>   Status: \(update.eventStatusDescription)")

                // Notify delegate about reducer response
                var errorMessage: String? = nil
                if case .failed(let message) = update.status {
                    errorMessage = message
                }

                await clientDelegate?.onReducerResponse(
                    client: self,
                    reducer: update.reducerName,
                    requestId: update.reducerCall.requestId,
                    status: update.eventStatusDescription,
                    message: errorMessage,
                    energyUsed: update.energyQuantaUsed.used
                )

                // Name changes will be detected and displayed by the delegate
                // when it compares the cached names with the new data

                // Process database updates
                for tableUpdate in update.databaseUpdate.tableUpdates {
                    debugLog(">>>   Table: \(tableUpdate.name) with \(tableUpdate.queryUpdates.count) query updates")

                    // Get the decoder for this table
                    let decoder = decoder(forTable: tableUpdate.name)

                    // Collect ALL deletes and inserts for this table across all QueryUpdates
                    var allDeletedRows: [Any] = []
                    var allInsertedRows: [Any] = []

                    // Process each CompressibleQueryUpdate in the table
                    for compUpdate in tableUpdate.queryUpdates {
                        guard case .uncompressed(let queryUpdate) = compUpdate else {
                            debugLog(">>>     Warning: Compressed updates not yet supported")
                            continue
                        }

                        debugLog(">>>     QueryUpdate: \(queryUpdate.deletes.rows.count) deletes, \(queryUpdate.inserts.rows.count) inserts")

                        // Debug: Check row data sizes
                        for (idx, row) in queryUpdate.deletes.rows.enumerated() {
                            debugLog(">>>       Delete row \(idx): \(row.count) bytes")
                        }
                        for (idx, row) in queryUpdate.inserts.rows.enumerated() {
                            debugLog(">>>       Insert row \(idx): \(row.count) bytes")
                        }

                        // Process deletes
                        if !queryUpdate.deletes.rows.isEmpty {
                            if let decoder {
                                for row in queryUpdate.deletes.rows {
                                    // Skip empty row data (common in TransactionUpdate)
                                    if row.isEmpty {
                                        continue
                                    }
                                    do {
                                        let reader = BSATNReader(data: row, debugEnabled: debugEnabled)
                                        let modelValue = try reader.readAlgebraicValue(as: .product(decoder.model))
                                        guard case .product(let values) = modelValue else { continue }
                                        let typedRow = try decoder.decode(modelValues: values)
                                        allDeletedRows.append(typedRow)
                                    } catch {
                                        debugLog(">>>     Error decoding deleted row: \(error)")
                                    }
                                }
                            } else {
                                // No decoder, pass raw data
                                for row in queryUpdate.deletes.rows where !row.isEmpty {
                                    allDeletedRows.append(row)
                                }
                            }
                        }

                        // Process inserts
                        if !queryUpdate.inserts.rows.isEmpty {
                            if let decoder {
                                for row in queryUpdate.inserts.rows {
                                    // Skip empty row data (common in TransactionUpdate)
                                    if row.isEmpty {
                                        continue
                                    }
                                    do {
                                        let reader = BSATNReader(data: row, debugEnabled: debugEnabled)
                                        let modelValue = try reader.readAlgebraicValue(as: .product(decoder.model))
                                        guard case .product(let values) = modelValue else { continue }
                                        let typedRow = try decoder.decode(modelValues: values)
                                        allInsertedRows.append(typedRow)
                                        if !isOwnUpdate {
                                            debugLog(">>>     📢 New row from OTHER USER: \(typedRow)")
                                        } else {
                                            debugLog(">>>     New row (own update): \(typedRow)")
                                        }
                                    } catch {
                                        debugLog(">>>     Error decoding inserted row: \(error)")
                                    }
                                }
                            } else {
                                // No decoder, pass raw data
                                for row in queryUpdate.inserts.rows where !row.isEmpty {
                                    allInsertedRows.append(row)
                                }
                            }
                        }
                    }

                    // Always call the delegate if we have any rows (even if just raw data)
                    if !allDeletedRows.isEmpty || !allInsertedRows.isEmpty {
                        debugLog(">>>   Calling onTableUpdate for '\(tableUpdate.name)': \(allDeletedRows.count) deletes, \(allInsertedRows.count) inserts")
                        await clientDelegate?.onTableUpdate(
                            client: self,
                            table: tableUpdate.name,
                            deletes: allDeletedRows,
                            inserts: allInsertedRows
                        )
                    } else {
                        debugLog(">>>   No rows to report for table '\(tableUpdate.name)'")
                    }
                }
            } else if messageTag == Tags.ServerMessage.oneOffQueryResponse.rawValue {
                // Read OneOffQueryResponse
                let response = try OneOffQueryResponse(reader: reader)
                debugLog(">>> OneOffQueryResponse received for messageId: \(response.messageId.map { String(format: "%02X", $0) }.joined())")
                
                if let error = response.error {
                    debugLog(">>> Query error: \(error)")
                } else {
                    debugLog(">>> Query successful with \(response.tables.count) tables")
                    for table in response.tables {
                        debugLog(">>>   Table: \(table.name) with \(table.rows.count) rows")
                    }
                }
                
                handleOneOffQueryResponse(response)
            } else if messageTag == Tags.ServerMessage.unsubscribeMultiApplied.rawValue {
                // Read UnsubscribeMultiAppliedMessage
                let unsubscribeMultiApplied = try UnsubscribeMultiAppliedMessage(reader: reader)
                debugLog(">>> UnsubscribeMultiApplied received for queryId: \(unsubscribeMultiApplied.queryId)")
                
                await clientDelegate?.onUnsubscribeApplied(client: self, queryId: unsubscribeMultiApplied.queryId)
            }
        } catch {
            debugLog(">>> Failed to decode: \(error)")
        }

        let onIncomingMessage = clientDelegate?.onIncomingMessage
        await onIncomingMessage?(self, data)
    }

    // MARK: - Hexadecimal Data Viewer

    /// Display data in hexadecimal format (16 bytes per line with offsets)
    private func printHexData(_ data: Data) {
        let bytes = Array(data)
        let bytesPerLine = 16
        let maxBytes = 16384  // Limit hex dump to first 16KB for debugging
        let bytesToPrint = min(bytes.count, maxBytes)

        for i in stride(from: 0, to: bytesToPrint, by: bytesPerLine) {
            // Print offset in hex
            print(String(format: "0x%08X: ", i), terminator: "")

            // Print hex bytes
            for j in 0..<bytesPerLine {
                if i + j < bytes.count {
                    print(String(format: "%02X ", bytes[i + j]), terminator: "")
                } else {
                    print("   ", terminator: "") // Padding for missing bytes
                }

                // Add extra space between groups of 8 bytes for readability
                if j == 7 && i + j < bytes.count {
                    print(" ", terminator: "")
                }
            }

            // Print ASCII representation
            print(" |", terminator: "")
            for j in 0..<bytesPerLine {
                if i + j < bytes.count {
                    let byte = bytes[i + j]
                    if byte >= 32 && byte <= 126 { // Printable ASCII range
                        print(String(format: "%c", byte), terminator: "")
                    } else {
                        print(".", terminator: "")
                    }
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

    // MARK: - Decompression Helpers

    /// Decompress Brotli data using native Compression framework
    private func decompressBrotli(data: Data) -> Data? {
        // Estimate decompressed size - use a much larger buffer for safety
        let decodedCapacity = max(data.count * 50, 1024 * 1024) // At least 1MB buffer
        let decodedBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: decodedCapacity)
        defer { decodedBuffer.deallocate() }

        debugLog(">>> Attempting Brotli decompression: \(data.count) bytes -> buffer: \(decodedCapacity) bytes")

        let decodedData: Data? = data.withUnsafeBytes { sourceBuffer in
            guard let sourcePtr = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }

            let decompressedSize = compression_decode_buffer(
                decodedBuffer, decodedCapacity,
                sourcePtr, data.count,
                nil, COMPRESSION_BROTLI
            )

            guard decompressedSize > 0 else {
                debugLog(">>> Brotli decompression failed, returned: \(decompressedSize)")
                return nil
            }
            debugLog(">>> Brotli decompression successful: \(decompressedSize) bytes")
            return Data(bytes: decodedBuffer, count: decompressedSize)
        }

        return decodedData
    }
}
