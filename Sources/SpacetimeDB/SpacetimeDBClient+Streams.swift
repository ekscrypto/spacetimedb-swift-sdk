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
    /// carries the full decoded `deletes` and `inserts` arrays for the
    /// transaction (no PK matching). For per-row events with `.updated`
    /// detection, see `rowEvents(table:)`.
    public nonisolated func tableEvents(named tableName: String) -> AsyncStream<TableEvent> {
        makeStream(register: { client, id, cont in
            await client.registerTableContinuation(id: id, tableName: tableName, continuation: cont)
        }, unregister: { client, id in
            await client.unregisterTableContinuation(id: id, tableName: tableName)
        })
    }

    /// Per-row stream for the named table. When the table's registered
    /// decoder conforms to `BSATNTableWithPrimaryKey`, delete+insert
    /// pairs sharing a PK within a single transaction are merged into
    /// `.updated(old:new:)` events. Tables without a PK only ever
    /// receive `.inserted` and `.deleted`.
    public nonisolated func rowEvents(table tableName: String) -> AsyncStream<RowEvent> {
        makeStream(register: { client, id, cont in
            await client.registerRowContinuation(id: id, tableName: tableName, continuation: cont)
        }, unregister: { client, id in
            await client.unregisterRowContinuation(id: id, tableName: tableName)
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

    /// Fan out a `TableEvent` to:
    ///   1. its own per-table batched stream (`tableEvents(named:)`), and
    ///   2. the per-row stream (`rowEvents(table:)`), with PK-matched
    ///      delete+insert pairs collapsed into `.updated(old:new:)` when
    ///      the registered decoder provides a `primaryKeyExtractor`.
    ///
    /// Folding row-event emission inside the existing TableEvent emit
    /// avoids introducing new actor-boundary transitions that would
    /// re-trigger Swift 6's `sending` data-race warnings.
    internal func emit(tableEvent event: TableEvent) {
        if let bucket = tableContinuations[event.tableName] {
            for cont in bucket.values { cont.yield(event) }
        }
        if let bucket = rowContinuations[event.tableName], !bucket.isEmpty {
            let extractor = decoder(forTable: event.tableName)?.primaryKeyExtractor
            let rowEvents: [RowEvent]
            if let extractor {
                rowEvents = Self.matchByPrimaryKey(deletes: event.deletes, inserts: event.inserts, extractor: extractor)
            } else {
                rowEvents = event.deletes.map { RowEvent.deleted($0) }
                          + event.inserts.map { RowEvent.inserted($0) }
            }
            for re in rowEvents {
                for cont in bucket.values { cont.yield(re) }
            }
        }
    }

    /// Pure helper — exposed `internal` for unit tests. Pairs deletes
    /// with inserts by primary key, emitting `.updated` for matches and
    /// `.deleted` / `.inserted` for the leftovers. Order: updates first,
    /// then deletions, then insertions.
    internal static func matchByPrimaryKey(
        deletes: [Any],
        inserts: [Any],
        extractor: @Sendable (Any) -> AnyHashable?
    ) -> [RowEvent] {
        var pendingInserts: [AnyHashable: Any] = [:]
        var orderedInsertKeys: [AnyHashable] = []
        var unkeyedInserts: [Any] = []

        for row in inserts {
            if let key = extractor(row) {
                if pendingInserts[key] == nil { orderedInsertKeys.append(key) }
                pendingInserts[key] = row
            } else {
                unkeyedInserts.append(row)
            }
        }

        var updates: [RowEvent] = []
        var unmatchedDeletes: [Any] = []
        for row in deletes {
            if let key = extractor(row), let newRow = pendingInserts.removeValue(forKey: key) {
                updates.append(.updated(old: row, new: newRow))
            } else {
                unmatchedDeletes.append(row)
            }
        }

        let unmatchedInserts: [Any] = orderedInsertKeys.compactMap { pendingInserts[$0] } + unkeyedInserts
        let deletions = unmatchedDeletes.map { RowEvent.deleted($0) }
        let insertions = unmatchedInserts.map { RowEvent.inserted($0) }
        return updates + deletions + insertions
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

    internal func registerRowContinuation(
        id: UUID,
        tableName: String,
        continuation: AsyncStream<RowEvent>.Continuation
    ) {
        rowContinuations[tableName, default: [:]][id] = continuation
    }

    internal func unregisterRowContinuation(id: UUID, tableName: String) {
        rowContinuations[tableName]?.removeValue(forKey: id)
        if rowContinuations[tableName]?.isEmpty == true {
            rowContinuations.removeValue(forKey: tableName)
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
