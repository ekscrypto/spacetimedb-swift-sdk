//
//  SpacetimeDBClient+oneOffQuery.swift
//  spacetimedb-swift-sdk
//
//  v2 OneOffQuery — single-shot SQL with no real-time updates.
//  Returns table-scoped row data; on server-side error, throws.
//

import Foundation
import BSATN

public enum OneOffQueryError: Error {
    case serverError(String)
    case timeout
}

extension SpacetimeDBClient {
    /// Run a one-off SQL `SELECT` and return the matching rows grouped
    /// by table. Throws `OneOffQueryError.serverError` if the server
    /// rejects the query, or `.timeout` if no response arrives in time.
    public func oneOffQuery(_ query: String, timeout: TimeInterval = 10.0) async throws -> [SingleTableRows] {
        guard let webSocketTask else { throw Errors.disconnected }
        let requestId = nextRequestId
        let request = OneOffQueryRequest(requestId: requestId, queryString: query)
        let payload = try request.encode()

        let message: OneOffQueryResultMessage = try await withCheckedThrowingContinuation { continuation in
            self.pendingOneOffQueries[requestId] = continuation
            Task {
                do {
                    try await webSocketTask.send(.data(payload))
                    Task {
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        self.timeoutOneOffQuery(requestId: requestId)
                    }
                } catch {
                    self.failOneOffQuery(requestId: requestId, error: error)
                }
            }
        }

        switch message.result {
        case .ok(let rows):
            return rows.tables
        case .error(let error):
            throw OneOffQueryError.serverError(error)
        }
    }

    /// Decode every row of a named table from a `SingleTableRows` array
    /// using the registered table-row decoder. Rows that fail to decode
    /// are skipped (errors are debug-logged).
    public func decodeRows<T>(from rows: [SingleTableRows], table tableName: String) async -> [T] {
        guard let table = rows.first(where: { $0.tableName == tableName }),
              let decoder = decoder(forTable: tableName)
        else { return [] }

        var decoded: [T] = []
        decoded.reserveCapacity(table.rows.rows.count)
        for (index, rowData) in table.rows.rows.enumerated() {
            do {
                let reader = BSATNReader(data: rowData, debugEnabled: debugEnabled)
                let typed = try decoder.decode(reader: reader)
                if let row = typed as? T {
                    decoded.append(row)
                }
            } catch {
                debugLog(">>> Failed to decode row \(index) from table \(tableName): \(error)")
            }
        }
        return decoded
    }

    // MARK: Resolution helpers (called from the receive loop)

    internal func resolveOneOffQuery(_ message: OneOffQueryResultMessage) {
        guard let cont = pendingOneOffQueries.removeValue(forKey: message.requestId) else { return }
        cont.resume(returning: message)
    }

    internal func failOneOffQuery(requestId: UInt32, error: Error) {
        if let cont = pendingOneOffQueries.removeValue(forKey: requestId) {
            cont.resume(throwing: error)
        }
    }

    internal func timeoutOneOffQuery(requestId: UInt32) {
        if let cont = pendingOneOffQueries.removeValue(forKey: requestId) {
            cont.resume(throwing: OneOffQueryError.timeout)
        }
    }
}
