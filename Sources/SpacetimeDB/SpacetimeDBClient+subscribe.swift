//
//  SpacetimeDBClient+subscribe.swift
//  spacetimedb-swift-sdk
//
//  Internal wire-level send helper for v2 Subscribe. The public
//  `subscribe(_:)` lives in SpacetimeDBClient+SubscriptionHandle.swift
//  and returns a typed `SubscriptionHandle`.
//

import Foundation
import BSATN

extension SpacetimeDBClient {
    /// Send a v2 Subscribe message over the wire. Caller is responsible
    /// for tracking the resulting query_set_id (typically via the
    /// returned `SubscriptionHandle`).
    internal func sendSubscribe(queries: [String], queryId: UInt32) async throws {
        guard let webSocketTask else { throw Errors.disconnected }
        let request = SubscribeRequest(
            requestId: nextRequestId,
            querySetId: QuerySetId(queryId),
            queryStrings: queries
        )
        let payload = try request.encode()
        try await webSocketTask.send(.data(payload))
    }
}
