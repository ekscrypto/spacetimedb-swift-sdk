//
//  SpacetimeDBClient+subscribe.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-28.
//

import Foundation
import BSATN

public extension SpacetimeDBClient {
    /// Subscribe to data changes using single subscription (non-multi)
    /// - Parameters:
    ///   - queries: Array of SQL query strings to subscribe to
    ///   - requestId: Optional request ID, will generate one if not provided
    /// - Returns: The request ID used for this subscription
    func subscribe(queries: [String], requestId: UInt32? = nil) async throws -> UInt32 {
        guard let webSocketTask else {
            throw Errors.disconnected
        }
        
        let actualRequestId = requestId ?? nextRequestId
        let request = SubscribeRequest(queries: queries, requestId: actualRequestId)
        let encodedRequest = try request.encode()
        
        var message = Data()
        message.append(Tags.ClientMessage.subscribe.rawValue)
        message.append(encodedRequest)
        
        try await webSocketTask.send(.data(message))
        return actualRequestId
    }
    
    /// Unsubscribe from a single subscription
    /// - Parameters:
    ///   - requestId: Optional request ID, will generate one if not provided
    ///   - queryId: The query ID to unsubscribe from
    /// - Returns: The request ID used for this unsubscription
    func unsubscribeSingle(requestId: UInt32? = nil, queryId: UInt32) async throws -> UInt32 {
        guard let webSocketTask else {
            throw Errors.disconnected
        }
        
        let actualRequestId = requestId ?? nextRequestId
        let request = UnsubscribeRequest(requestId: actualRequestId, queryId: queryId)
        let encodedRequest = try request.encode()
        
        var message = Data()
        message.append(Tags.ClientMessage.unsubscribe.rawValue)
        message.append(encodedRequest)
        
        try await webSocketTask.send(.data(message))
        return actualRequestId
    }
}