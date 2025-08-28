//
//  SpacetimeDBClient+Unsubscribe.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-28.
//

import Foundation
import BSATN

extension SpacetimeDBClient {
    
    public func unsubscribe(queryId: UInt32) async throws {
        guard connected else {
            throw Errors.disconnected
        }
        
        debugLog(">>> Unsubscribing from queryId: \(queryId)")
        
        let requestId = nextRequestId
        let request = UnsubscribeMultiRequest(requestId: requestId, queryId: queryId)
        let encodedRequest = try request.encode()
        
        // Create message with tag and encoded payload
        var message = Data()
        message.append(Tags.ClientMessage.unsubscribeMulti.rawValue)
        message.append(encodedRequest)
        
        // Send the message
        guard let webSocketTask = webSocketTask else {
            throw Errors.disconnected
        }
        
        try await webSocketTask.send(.data(message))
        debugLog(">>> Unsubscribe request sent for queryId: \(queryId)")
    }
}