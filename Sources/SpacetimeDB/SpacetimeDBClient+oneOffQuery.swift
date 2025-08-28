//
//  SpacetimeDBClient+oneOffQuery.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-27.
//

import Foundation
import BSATN

public struct OneOffQueryResult: Sendable {
    public let messageId: Data
    public let error: String?
    public let tables: [OneOffTable]
    public let executionDuration: UInt64
    
    /// Decode rows from a table using the client's registered decoder
    public func decodeRows<T>(from tableName: String, using client: SpacetimeDBClient) async -> [T] {
        guard let table = tables.first(where: { $0.name == tableName }),
              let decoder = await client.decoder(forTable: tableName) else {
            return []
        }
        
        var decodedRows: [T] = []
        for (index, rowData) in table.rows.enumerated() {
            do {
                let reader = BSATNReader(data: rowData, debugEnabled: client.debugEnabled)
                let modelValue = try reader.readAlgebraicValue(as: .product(decoder.model))
                guard case .product(let values) = modelValue else { continue }
                let typedRow = try decoder.decode(modelValues: values)
                if let row = typedRow as? T {
                    decodedRows.append(row)
                }
            } catch {
                debugLog("Failed to decode row \(index) from table \(tableName): \(error)")
            }
        }
        return decodedRows
    }
}

extension SpacetimeDBClient {
    /// Execute a one-time SQL query without establishing a subscription
    /// - Parameter query: The SQL query string to execute
    /// - Returns: A OneOffQueryResult containing the query results or error
    /// - Throws: An error if the query fails to send or times out
    public func oneOffQuery(_ queryString: String, timeout: TimeInterval = 10.0) async throws -> OneOffQueryResult {
        guard let webSocketTask else {
            throw SpacetimeDBErrors.notConnected
        }
        
        // Generate unique message ID
        let messageId = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        
        let request = OneOffQueryRequest(messageId: messageId, queryString: queryString)
        let encodedRequest = try request.encode()
        
        debugLog(">>> Sending OneOffQuery: \(queryString)")
        debugLog(">>> Message ID: \(messageId.map { String(format: "%02X", $0) }.joined())")
        
        // Create a continuation to wait for the response
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                // Store the continuation for this message ID
                await self.addPendingOneOffQuery(messageId: messageId, continuation: continuation)
                
                // Send the request
                do {
                    try await webSocketTask.send(URLSessionWebSocketTask.Message.data(encodedRequest))
                    
                    // Set up timeout
                    Task {
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        await self.timeoutOneOffQuery(messageId: messageId)
                    }
                } catch {
                    await self.removePendingOneOffQuery(messageId: messageId)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Internal OneOffQuery Management
    
    internal func addPendingOneOffQuery(messageId: Data, continuation: CheckedContinuation<OneOffQueryResult, Error>) {
        pendingOneOffQueries[messageId] = continuation
    }
    
    internal func removePendingOneOffQuery(messageId: Data) {
        pendingOneOffQueries.removeValue(forKey: messageId)
    }
    
    internal func timeoutOneOffQuery(messageId: Data) {
        if let continuation = pendingOneOffQueries[messageId] {
            pendingOneOffQueries.removeValue(forKey: messageId)
            continuation.resume(throwing: SpacetimeDBErrors.timeout)
        }
    }
    
    internal func handleOneOffQueryResponse(_ response: OneOffQueryResponse) {
        let result = OneOffQueryResult(
            messageId: response.messageId,
            error: response.error,
            tables: response.tables,
            executionDuration: response.totalHostExecutionDuration
        )
        
        // Call delegate method
        Task {
            await clientDelegate?.onOneOffQueryResponse(client: self, result: result)
        }
        
        // Resume waiting continuation if any
        if let continuation = pendingOneOffQueries[response.messageId] {
            pendingOneOffQueries.removeValue(forKey: response.messageId)
            continuation.resume(returning: result)
        }
    }
}