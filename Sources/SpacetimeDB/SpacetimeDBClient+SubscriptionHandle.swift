//
//  SpacetimeDBClient+SubscriptionHandle.swift
//  spacetimedb-swift-sdk
//
//  Actor-side support for SubscriptionHandle:
//   • `subscribe(_:)` creates a handle.
//   • Pending-applied / pending-unsubscribe continuation registries
//     are resolved by the receive loop.
//

import Foundation
import BSATN

extension SpacetimeDBClient {

    // MARK: Public handle-returning subscribe API

    /// Subscribe to one or more SQL queries. Returns immediately with a
    /// `SubscriptionHandle`; await `handle.applied()` to know when the
    /// initial row data has landed.
    public func subscribe(_ queries: [String]) async throws -> SubscriptionHandle {
        let queryId = self.nextQueryId
        try await sendSubscribe(queries: queries, queryId: queryId)
        return SubscriptionHandle(queryId: queryId, queries: queries, client: self)
    }

    /// Convenience: emit `SELECT * FROM <table>` for every currently-
    /// registered table-row decoder and subscribe to the lot. Returns
    /// a single `SubscriptionHandle`.
    @discardableResult
    public func subscribeToAllTables() async throws -> SubscriptionHandle {
        let tables = registeredTableNames()
        guard !tables.isEmpty else {
            throw SpacetimeDBError.invalidDefinition(
                "subscribeToAllTables called before any table decoder was registered"
            )
        }
        let queries = tables.sorted().map { "SELECT * FROM \($0)" }
        return try await subscribe(queries)
    }

    // MARK: Pending-event registries

    internal func awaitSubscriptionApplied(queryId: UInt32) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pendingAppliedContinuations[queryId, default: []].append(cont)
        }
    }

    internal func unsubscribeAndAwait(queryId: UInt32, includeDroppedRows: Bool) async throws {
        try await sendUnsubscribe(queryId: queryId, includeDroppedRows: includeDroppedRows)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pendingUnsubscribeContinuations[queryId, default: []].append(cont)
        }
    }

    // MARK: Resolution helpers (called from the receive loop)

    internal func resolveSubscriptionApplied(queryId: UInt32) {
        guard let conts = pendingAppliedContinuations.removeValue(forKey: queryId) else { return }
        for cont in conts { cont.resume() }
    }

    internal func resolveSubscriptionUnsubscribed(queryId: UInt32) {
        guard let conts = pendingUnsubscribeContinuations.removeValue(forKey: queryId) else { return }
        for cont in conts { cont.resume() }
    }

    /// Fail any pending `applied()` or `unsubscribe()` futures whose
    /// `queryId` matches.
    internal func failSubscriptionFutures(queryId: UInt32, message: String) {
        let error = SpacetimeDBError.invalidDefinition(message)
        pendingAppliedContinuations.removeValue(forKey: queryId)?.forEach { $0.resume(throwing: error) }
        pendingUnsubscribeContinuations.removeValue(forKey: queryId)?.forEach { $0.resume(throwing: error) }
    }

    /// Fail every pending future on disconnect.
    internal func failAllSubscriptionFutures(reason: String) {
        let error = SpacetimeDBError.disconnected
        for (_, conts) in pendingAppliedContinuations {
            for cont in conts { cont.resume(throwing: error) }
        }
        pendingAppliedContinuations.removeAll()
        for (_, conts) in pendingUnsubscribeContinuations {
            for cont in conts { cont.resume(throwing: error) }
        }
        pendingUnsubscribeContinuations.removeAll()

        // Also fail in-flight reducer/procedure calls.
        let callError = SpacetimeDBError.disconnected
        for (_, pending) in pendingReducerCalls {
            pending.continuation.resume(throwing: callError)
        }
        pendingReducerCalls.removeAll()
        for (_, pending) in pendingProcedureCalls {
            pending.continuation.resume(throwing: callError)
        }
        pendingProcedureCalls.removeAll()
        // Drain pending one-off queries similarly.
        for (_, cont) in pendingOneOffQueries {
            cont.resume(throwing: callError)
        }
        pendingOneOffQueries.removeAll()

        _ = reason
    }
}
