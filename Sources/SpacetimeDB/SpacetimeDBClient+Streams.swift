//
//  SpacetimeDBClient+Streams.swift
//  spacetimedb-swift-sdk
//
//  Phase 3: AsyncStream event surface. The streams API runs in parallel
//  with the legacy `SpacetimeDBClientDelegate` — both fire from the same
//  receive loop, so application code may pick either or both.
//
//  Multi-subscriber model: each accessor returns a fresh `AsyncStream`
//  whose continuation registers itself in a per-channel `[UUID: Cont]`
//  dictionary on the actor. When the consuming `Task` cancels (or simply
//  exits its `for await` loop), the stream's `onTermination` closure
//  unregisters itself, so there is no leak.
//

import Foundation

extension SpacetimeDBClient {

    // MARK: Public stream accessors

    /// Connection-lifecycle events: `connected`, `reconnecting`,
    /// `disconnected`, `error`. Each subscriber gets its own stream;
    /// emissions fan out to all live subscribers.
    public nonisolated var connectionEvents: AsyncStream<ConnectionEvent> {
        makeStream(register: { client, id, cont in
            await client.registerConnectionContinuation(id: id, continuation: cont)
        }, unregister: { client, id in
            await client.unregisterConnectionContinuation(id: id)
        })
    }

    /// Typed reducer-response events. Fires once per `TransactionUpdate`
    /// with the typed `ReducerStatus` and `EnergyQuanta`.
    public nonisolated var reducerEvents: AsyncStream<ReducerEvent> {
        makeStream(register: { client, id, cont in
            await client.registerReducerContinuation(id: id, continuation: cont)
        }, unregister: { client, id in
            await client.unregisterReducerContinuation(id: id)
        })
    }

    /// Subscription-lifecycle events: applied, unsubscribed, error. Covers
    /// both single and multi subscriptions (distinguished by the `multi`
    /// flag on the `applied` / `unsubscribed` cases).
    public nonisolated var subscriptionEvents: AsyncStream<SubscriptionLifecycleEvent> {
        makeStream(register: { client, id, cont in
            await client.registerSubscriptionContinuation(id: id, continuation: cont)
        }, unregister: { client, id in
            await client.unregisterSubscriptionContinuation(id: id)
        })
    }

    /// Per-table batched updates for the named table. Each `TableEvent`
    /// carries decoded `deletes` and `inserts` arrays. Phase 6 will add a
    /// strongly typed per-table stream with primary-key-based update
    /// detection.
    public nonisolated func tableEvents(named tableName: String) -> AsyncStream<TableEvent> {
        makeStream(register: { client, id, cont in
            await client.registerTableContinuation(id: id, tableName: tableName, continuation: cont)
        }, unregister: { client, id in
            await client.unregisterTableContinuation(id: id, tableName: tableName)
        })
    }

    // MARK: Internal emission (called from the receive loop)

    internal func emit(connection event: ConnectionEvent) {
        for cont in connectionContinuations.values { cont.yield(event) }
    }

    internal func emit(reducer event: ReducerEvent) {
        for cont in reducerContinuations.values { cont.yield(event) }
    }

    internal func emit(subscription event: SubscriptionLifecycleEvent) {
        for cont in subscriptionContinuations.values { cont.yield(event) }
    }

    internal func emit(tableEvent event: TableEvent) {
        guard let bucket = tableContinuations[event.tableName] else { return }
        for cont in bucket.values { cont.yield(event) }
    }


    // MARK: Internal registration (actor-isolated)

    internal func registerConnectionContinuation(
        id: UUID,
        continuation: AsyncStream<ConnectionEvent>.Continuation
    ) {
        connectionContinuations[id] = continuation
    }

    internal func unregisterConnectionContinuation(id: UUID) {
        connectionContinuations.removeValue(forKey: id)
    }

    internal func registerReducerContinuation(
        id: UUID,
        continuation: AsyncStream<ReducerEvent>.Continuation
    ) {
        reducerContinuations[id] = continuation
    }

    internal func unregisterReducerContinuation(id: UUID) {
        reducerContinuations.removeValue(forKey: id)
    }

    internal func registerSubscriptionContinuation(
        id: UUID,
        continuation: AsyncStream<SubscriptionLifecycleEvent>.Continuation
    ) {
        subscriptionContinuations[id] = continuation
    }

    internal func unregisterSubscriptionContinuation(id: UUID) {
        subscriptionContinuations.removeValue(forKey: id)
    }

    internal func registerTableContinuation(
        id: UUID,
        tableName: String,
        continuation: AsyncStream<TableEvent>.Continuation
    ) {
        tableContinuations[tableName, default: [:]][id] = continuation
    }

    internal func unregisterTableContinuation(id: UUID, tableName: String) {
        tableContinuations[tableName]?.removeValue(forKey: id)
        if tableContinuations[tableName]?.isEmpty == true {
            tableContinuations.removeValue(forKey: tableName)
        }
    }
}

// MARK: Stream-builder helper

extension SpacetimeDBClient {
    private nonisolated func makeStream<Event: Sendable>(
        register: @Sendable @escaping (SpacetimeDBClient, UUID, AsyncStream<Event>.Continuation) async -> Void,
        unregister: @Sendable @escaping (SpacetimeDBClient, UUID) async -> Void
    ) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let id = UUID()
            let weakSelf = WeakClient(self)
            Task { [weakSelf] in
                guard let client = weakSelf.client else { return }
                await register(client, id, continuation)
            }
            continuation.onTermination = { @Sendable [weakSelf] _ in
                Task { [weakSelf] in
                    guard let client = weakSelf.client else { return }
                    await unregister(client, id)
                }
            }
        }
    }
}

/// Sendable weak-reference shim — `weak var` capture lists aren't directly
/// usable in `@Sendable` closures because `weak` requires a class context.
/// The actor itself is a class, so this is safe.
private struct WeakClient: @unchecked Sendable {
    weak var client: SpacetimeDBClient?
    init(_ client: SpacetimeDBClient) { self.client = client }
}
