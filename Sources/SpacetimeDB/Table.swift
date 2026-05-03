//
//  Table.swift
//  spacetimedb-swift-sdk
//
//  Phase 11: typed `Table<Row>` view — a cached, callback-driven mirror
//  of a SpacetimeDB table. Mirrors the TS v3 `connection.db.<tableName>`
//  surface: `count`, `iter()`, `onInsert/onDelete/onUpdate`, and (for PK
//  tables) `find(_:)`.
//
//  A `Table` owns a consumer task that drains `client.rowEvents(table:)`
//  and folds events into an internal cache. The cache uses a small
//  inverted index keyed by the row's primary key when present, which
//  gives O(1) `find` for PK tables; non-PK tables fall back to an
//  Equatable linear scan on delete.
//
//  Shape contract: callbacks are invoked on the actor's executor. Don't
//  re-enter the table from a callback (the actor lock would block).
//  Snapshot what you need and continue work outside.
//

import Foundation
import BSATN

public actor Table<Row: BSATNRow & Equatable & Sendable> {

    public typealias CallbackToken = UUID

    private var entries: [Row] = []
    private var pkIndex: [AnyHashable: Int] = [:]

    private var insertCallbacks: [CallbackToken: @Sendable (Row) -> Void] = [:]
    private var deleteCallbacks: [CallbackToken: @Sendable (Row) -> Void] = [:]
    private var updateCallbacks: [CallbackToken: @Sendable (Row, Row) -> Void] = [:]

    nonisolated(unsafe) private var consumerTask: Task<Void, Never>?

    /// Attach the table cache to a `SpacetimeDBClient`. Awaits
    /// `client.rowEvents(table:)` synchronously inside the actor so the
    /// continuation registers before the init returns — no events lost.
    public init(client: SpacetimeDBClient) async {
        let stream = await client.rowEvents(table: Row.tableName)
        let weakSelf = WeakTable(self)
        consumerTask = Task { [weakSelf] in
            for await event in stream {
                if Task.isCancelled { break }
                await weakSelf.table?.apply(event)
            }
        }
    }

    deinit {
        consumerTask?.cancel()
    }

    // MARK: Public accessors

    /// Number of rows currently cached.
    public var count: Int { entries.count }

    /// Snapshot of every cached row, in insertion order.
    public func iter() -> [Row] { entries }

    /// Convenience: returns the rows that satisfy `predicate`. Snapshots
    /// the cache, so the result is safe to use after the actor releases.
    public func filter(_ predicate: @Sendable (Row) -> Bool) -> [Row] {
        entries.filter(predicate)
    }

    // MARK: Callback registration

    /// Register a callback fired for every `.inserted` row event.
    /// Returns a token; pass it to `removeOnInsert(_:)` to unregister.
    @discardableResult
    public func onInsert(_ callback: @escaping @Sendable (Row) -> Void) -> CallbackToken {
        let token = UUID()
        insertCallbacks[token] = callback
        return token
    }

    public func removeOnInsert(_ token: CallbackToken) {
        insertCallbacks.removeValue(forKey: token)
    }

    /// Register a callback fired for every `.deleted` row event.
    @discardableResult
    public func onDelete(_ callback: @escaping @Sendable (Row) -> Void) -> CallbackToken {
        let token = UUID()
        deleteCallbacks[token] = callback
        return token
    }

    public func removeOnDelete(_ token: CallbackToken) {
        deleteCallbacks.removeValue(forKey: token)
    }

    // MARK: Internal: row event application

    private func apply(_ event: RowEvent) {
        switch event {
        case .inserted(let any):
            guard let row = any as? Row else { return }
            applyInsert(row)
            for callback in insertCallbacks.values { callback(row) }
        case .deleted(let any):
            guard let row = any as? Row else { return }
            applyDelete(row)
            for callback in deleteCallbacks.values { callback(row) }
        case .updated(let oldAny, let newAny):
            guard let oldRow = oldAny as? Row, let newRow = newAny as? Row else { return }
            applyUpdate(old: oldRow, new: newRow)
            for callback in updateCallbacks.values { callback(oldRow, newRow) }
        }
    }

    private func applyInsert(_ row: Row) {
        if let pk = primaryKey(of: row) {
            if let existingIndex = pkIndex[pk] {
                entries[existingIndex] = row
                return
            }
            pkIndex[pk] = entries.count
        }
        entries.append(row)
    }

    private func applyDelete(_ row: Row) {
        let removedIndex: Int?
        if let pk = primaryKey(of: row), let idx = pkIndex.removeValue(forKey: pk) {
            removedIndex = idx
        } else {
            removedIndex = entries.firstIndex(of: row)
        }
        guard let idx = removedIndex else { return }
        entries.remove(at: idx)
        for (k, v) in pkIndex where v > idx {
            pkIndex[k] = v - 1
        }
    }

    private func applyUpdate(old: Row, new: Row) {
        if let pk = primaryKey(of: new), let idx = pkIndex[pk] {
            entries[idx] = new
            return
        }
        if let idx = entries.firstIndex(of: old) {
            entries[idx] = new
        }
    }

    private func primaryKey(of row: Row) -> AnyHashable? {
        guard let pkRow = row as? any BSATNTableWithPrimaryKey else { return nil }
        return AnyHashable(pkRow.primaryKey)
    }

    // MARK: Internal access for PK-only extension

    fileprivate func registerUpdateCallback(_ callback: @escaping @Sendable (Row, Row) -> Void) -> CallbackToken {
        let token = UUID()
        updateCallbacks[token] = callback
        return token
    }

    fileprivate func unregisterUpdateCallback(_ token: CallbackToken) {
        updateCallbacks.removeValue(forKey: token)
    }

    fileprivate func lookup(by pk: AnyHashable) -> Row? {
        guard let idx = pkIndex[pk] else { return nil }
        return entries[idx]
    }
}

public extension Table where Row: BSATNTableWithPrimaryKey {
    /// O(1) lookup by primary key.
    func find(_ primaryKey: Row.PrimaryKey) -> Row? {
        lookup(by: AnyHashable(primaryKey))
    }

    /// Register a callback fired when a row's PK-matched delete+insert
    /// pair is collapsed into an `.updated(old:new:)` event.
    @discardableResult
    func onUpdate(_ callback: @escaping @Sendable (Row, Row) -> Void) -> CallbackToken {
        registerUpdateCallback(callback)
    }

    func removeOnUpdate(_ token: CallbackToken) {
        unregisterUpdateCallback(token)
    }
}

private struct WeakTable<Row: BSATNRow & Equatable & Sendable>: @unchecked Sendable {
    weak var table: Table<Row>?
    init(_ table: Table<Row>) { self.table = table }
}
