//
//  SubscriptionHandle.swift
//  spacetimedb-swift-sdk
//
//  Handle returned from `client.subscribe(...)` — wraps the underlying
//  v2 query_set_id with awaitable / cancellable semantics plus a
//  per-handle event stream.
//

import Foundation

public struct SubscriptionHandle: Sendable {
    /// Client-supplied opaque identifier for this subscription.
    /// On the wire it travels as `QuerySetId{ id }`.
    public let queryId: UInt32

    /// The queries this handle subscribes to. Stored on the client side
    /// only — the server identifies the subscription by `queryId`.
    public let queries: [String]

    private let client: SpacetimeDBClient

    internal init(queryId: UInt32, queries: [String], client: SpacetimeDBClient) {
        self.queryId = queryId
        self.queries = queries
        self.client = client
    }

    /// Suspends until the server confirms the subscription with
    /// `SubscribeApplied`, or throws if it fails.
    public func applied() async throws {
        try await client.awaitSubscriptionApplied(queryId: queryId)
    }

    /// Per-handle filtered stream of subscription-lifecycle events for
    /// this `queryId` only. Each subscriber gets its own stream.
    ///
    /// `async` so the upstream `client.subscriptionEvents` continuation
    /// registers synchronously inside the actor before this method
    /// returns — otherwise events emitted between accessor return and
    /// the inner forwarding task starting would be lost.
    public func events() async -> AsyncStream<SubscriptionLifecycleEvent> {
        let queryId = self.queryId
        let upstream = await client.subscriptionEvents
        return AsyncStream { continuation in
            let task = Task {
                for await event in upstream {
                    switch event {
                    case .applied(let qid),
                         .unsubscribed(let qid):
                        if qid == queryId { continuation.yield(event) }
                    case .error(let qid, _, _):
                        if qid == queryId { continuation.yield(event) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Sends an `Unsubscribe` request and suspends until the server
    /// confirms. Set `includeDroppedRows` to receive the rows being
    /// removed from the client cache in the response.
    public func unsubscribe(includeDroppedRows: Bool = false) async throws {
        try await client.unsubscribeAndAwait(queryId: queryId, includeDroppedRows: includeDroppedRows)
    }
}
