//
//  SpacetimeDBClient+subscribeMulti.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation

extension SpacetimeDBClient {
    public func subscribeMulti(queries: [String], queryId: UInt32) async throws -> UInt32 {
        guard let webSocketTask else {
            throw SpacetimeDBErrors.notConnected
        }

        let requestId = nextRequestId
        let request = try SubscribeMultiRequest(queries: queries, requestId: requestId, queryId: queryId).encode()
        try await webSocketTask.send(URLSessionWebSocketTask.Message.data(request))
        return requestId
    }
}
