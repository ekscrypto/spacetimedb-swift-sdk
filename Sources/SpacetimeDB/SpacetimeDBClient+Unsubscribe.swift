//
//  SpacetimeDBClient+Unsubscribe.swift
//  spacetimedb-swift-sdk
//
//  Internal wire-level send helper for v2 Unsubscribe.
//  Public callers go through `SubscriptionHandle.unsubscribe(...)`.
//

import Foundation
import BSATN

extension SpacetimeDBClient {
    internal func sendUnsubscribe(queryId: UInt32, includeDroppedRows: Bool) async throws {
        guard let webSocketTask else { throw Errors.disconnected }
        let request = UnsubscribeRequest(
            requestId: nextRequestId,
            querySetId: QuerySetId(queryId),
            flags: includeDroppedRows ? .sendDroppedRows : .default
        )
        let payload = try request.encode()
        try await webSocketTask.send(.data(payload))
    }
}
