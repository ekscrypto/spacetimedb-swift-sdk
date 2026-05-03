//
//  SubscriptionHandle.swift
//  spacetimedb-swift-sdk
//
//  Phase 4: typed handle returned from `client.subscribe(...)`.
//  Replaces the bare-`UInt32` queryId with an awaitable, cancellable
//  object that exposes the subscription's lifecycle as async/await
//  + an AsyncStream of per-handle events.
//

import Foundation

public struct SubscriptionHandle: Sendable {
    public let queryId: UInt32
    /// `true` if this handle was created via `subscribe(...)` (multi-query
    /// protocol path); `false` for `subscribeSingle(...)`.
    public let isMulti: Bool

    /// The queries this handle subscribes to. Stored on the client side
    /// only — the server identifies the subscription by `queryId`.
    public let queries: [String]

    private let client: SpacetimeDBClient

    internal init(
        queryId: UInt32,
        isMulti: Bool,
        queries: [String],
        client: SpacetimeDBClient
    ) {
        self.queryId = queryId
        self.isMulti = isMulti
        self.queries = queries
        self.client = client
    }

    /// Suspends until the server confirms the subscription with
    /// `SubscribeApplied` / `SubscribeMultiApplied`, or throws if the
    /// subscription fails. Calling more than once will throw on the
    /// second call (one-shot semantics, like a future).
    public func applied() async throws {
        try await client.awaitSubscriptionApplied(queryId: queryId, multi: isMulti)
    }

    /// Per-handle filtered stream of subscription-lifecycle events
    /// (`.applied`, `.unsubscribed`, `.error`) for this subscription's
    /// `queryId` only. Each subscriber gets its own stream.
    ///
    /// `async` so the upstream `client.subscriptionEvents` continuation
    /// registers synchronously inside the SDK actor *before* this method
    /// returns — otherwise events emitted between accessor return and
    /// the inner forwarding task starting would be lost.
    public func events() async -> AsyncStream<SubscriptionLifecycleEvent> {
        let queryId = self.queryId
        let upstream = await client.subscriptionEvents
        return AsyncStream { continuation in
            let task = Task {
                for await event in upstream {
                    switch event {
                    case .applied(let qid, _),
                         .unsubscribed(let qid, _):
                        if qid == queryId { continuation.yield(event) }
                    case .error(let qid, _, _):
                        if qid == nil || qid == queryId { continuation.yield(event) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Sends an `Unsubscribe` / `UnsubscribeMulti` request and suspends
    /// until the server confirms. Throws if the connection drops or the
    /// server reports an error against this `queryId`.
    public func unsubscribe() async throws {
        try await client.unsubscribeAndAwait(queryId: queryId, multi: isMulti)
    }
}
