//
//  SpacetimeDBClient+Streams.swift
//  spacetimedb-swift-sdk
//
//  Phase 3: AsyncStream event surface. The streams API runs in parallel
//  with the legacy `SpacetimeDBClientDelegate` — both fire from the same
//  receive loop, so application code may pick either or both.
//
//  Multi-subscriber model: each accessor returns a fresh `AsyncStream`
//  whose continuation is registered in a per-channel `[UUID: Cont]`
//  dictionary on the actor at the moment the property is awaited
//  (synchronously inside the `AsyncStream` builder). When the consuming
//  `Task` cancels (or simply exits its `for await` loop), the stream's
//  `onTermination` closure schedules unregistration on the actor, so
//  there is no leak.
//
//  Note: accessors are actor-isolated (caller must `await`). Earlier
//  iterations of this file used `nonisolated var` accessors that hopped
//  to the actor via a fire-and-forget `Task` to register, which lost
//  events fired between accessor return and the registration Task's
//  first dispatch. The actor-isolated form eliminates that race.
//

import Foundation

extension SpacetimeDBClient {

    // MARK: Public stream accessors

    /// Connection-lifecycle events: `connected`, `reconnecting`,
    /// `disconnected`, `error`. Each subscriber gets its own stream;
    /// emissions fan out to all live subscribers.
    public var connectionEvents: AsyncStream<ConnectionEvent> {
        AsyncStream { continuation in
            let id = UUID()
            self.connectionContinuations[id] = continuation
            let weakSelf = WeakClient(self)
            continuation.onTermination = { @Sendable [weakSelf] _ in
                Task { [weakSelf] in
                    await weakSelf.client?.unregisterConnectionContinuation(id: id)
                }
            }
        }
    }

    /// Typed reducer-response events. Fires once per `TransactionUpdate`
    /// with the typed `ReducerStatus` and `EnergyQuanta`.
    public var reducerEvents: AsyncStream<ReducerEvent> {
        AsyncStream { continuation in
            let id = UUID()
            self.reducerContinuations[id] = continuation
            let weakSelf = WeakClient(self)
            continuation.onTermination = { @Sendable [weakSelf] _ in
                Task { [weakSelf] in
                    await weakSelf.client?.unregisterReducerContinuation(id: id)
                }
            }
        }
    }

    /// Subscription-lifecycle events: applied, unsubscribed, error. Covers
    /// both single and multi subscriptions (distinguished by the `multi`
    /// flag on the `applied` / `unsubscribed` cases).
    public var subscriptionEvents: AsyncStream<SubscriptionLifecycleEvent> {
        AsyncStream { continuation in
            let id = UUID()
            self.subscriptionContinuations[id] = continuation
            let weakSelf = WeakClient(self)
            continuation.onTermination = { @Sendable [weakSelf] _ in
                Task { [weakSelf] in
                    await weakSelf.client?.unregisterSubscriptionContinuation(id: id)
                }
            }
        }
    }

    /// Per-table batched updates for the named table. Each `TableEvent`
    /// carries the full decoded `deletes` and `inserts` arrays for the
    /// transaction (no PK matching). For per-row events with `.updated`
    /// detection, see `rowEvents(table:)`.
    public func tableEvents(named tableName: String) -> AsyncStream<TableEvent> {
        AsyncStream { continuation in
            let id = UUID()
            self.tableContinuations[tableName, default: [:]][id] = continuation
            let weakSelf = WeakClient(self)
            continuation.onTermination = { @Sendable [weakSelf] _ in
                Task { [weakSelf] in
                    await weakSelf.client?.unregisterTableContinuation(id: id, tableName: tableName)
                }
            }
        }
    }

    /// Per-row stream for the named table. When the table's registered
    /// decoder conforms to `BSATNTableWithPrimaryKey`, delete+insert
    /// pairs sharing a PK within a single transaction are merged into
    /// `.updated(old:new:)` events. Tables without a PK only ever
    /// receive `.inserted` and `.deleted`.
    public func rowEvents(table tableName: String) -> AsyncStream<RowEvent> {
        AsyncStream { continuation in
            let id = UUID()
            self.rowContinuations[tableName, default: [:]][id] = continuation
            let weakSelf = WeakClient(self)
            continuation.onTermination = { @Sendable [weakSelf] _ in
                Task { [weakSelf] in
                    await weakSelf.client?.unregisterRowContinuation(id: id, tableName: tableName)
                }
            }
        }
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


    // MARK: Internal unregistration (actor-isolated; called by onTermination)

    internal func unregisterConnectionContinuation(id: UUID) {
        connectionContinuations.removeValue(forKey: id)
    }

    internal func unregisterReducerContinuation(id: UUID) {
        reducerContinuations.removeValue(forKey: id)
    }

    internal func unregisterSubscriptionContinuation(id: UUID) {
        subscriptionContinuations.removeValue(forKey: id)
    }

    internal func unregisterTableContinuation(id: UUID, tableName: String) {
        tableContinuations[tableName]?.removeValue(forKey: id)
        if tableContinuations[tableName]?.isEmpty == true {
            tableContinuations.removeValue(forKey: tableName)
        }
    }

    internal func unregisterRowContinuation(id: UUID, tableName: String) {
        rowContinuations[tableName]?.removeValue(forKey: id)
        if rowContinuations[tableName]?.isEmpty == true {
            rowContinuations.removeValue(forKey: tableName)
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
