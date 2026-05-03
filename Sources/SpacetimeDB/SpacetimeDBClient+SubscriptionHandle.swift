//
//  SpacetimeDBClient+SubscriptionHandle.swift
//  spacetimedb-swift-sdk
//
//  Phase 4: actor-side support for SubscriptionHandle —
//   • `subscribe(_:)` / `subscribeSingle(_:)` create handles.
//   • Pending-applied / pending-unsubscribe continuation registries
//     are resolved by the receive loop.
//

import Foundation
import BSATN

extension SpacetimeDBClient {

    // MARK: Public handle-returning subscribe API

    /// Subscribe to one or more SQL queries using the multi-subscription
    /// protocol. Returns immediately with a `SubscriptionHandle`; await
    /// `handle.applied()` to know when the initial row data has landed.
    public func subscribe(_ queries: [String]) async throws -> SubscriptionHandle {
        let queryId = self.nextQueryId
        _ = try await subscribeMulti(queries: queries, queryId: queryId)
        return SubscriptionHandle(queryId: queryId, isMulti: true, queries: queries, client: self)
    }

    /// Subscribe to one or more SQL queries using the single-subscription
    /// protocol (legacy `Subscribe` message). Returns a `SubscriptionHandle`.
    public func subscribeSingle(_ queries: [String]) async throws -> SubscriptionHandle {
        let queryId = self.nextQueryId
        _ = try await subscribe(queries: queries, requestId: queryId)
        return SubscriptionHandle(queryId: queryId, isMulti: false, queries: queries, client: self)
    }

    // MARK: Pending-event registries

    internal func awaitSubscriptionApplied(queryId: UInt32, multi: Bool) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pendingAppliedContinuations[queryId, default: []].append(cont)
        }
    }

    internal func unsubscribeAndAwait(queryId: UInt32, multi: Bool) async throws {
        // Send the unsubscribe request, then wait for the matching applied event.
        if multi {
            try await unsubscribe(queryId: queryId)
        } else {
            _ = try await unsubscribeSingle(queryId: queryId)
        }
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
    /// `queryId` matches (or all of them if `queryId` is `nil`, which is
    /// what the server sends for connection-wide subscription errors).
    internal func failSubscriptionFutures(queryId: UInt32?, message: String) {
        let error = SpacetimeDBError.invalidDefinition(message)
        if let qid = queryId {
            pendingAppliedContinuations.removeValue(forKey: qid)?.forEach { $0.resume(throwing: error) }
            pendingUnsubscribeContinuations.removeValue(forKey: qid)?.forEach { $0.resume(throwing: error) }
        } else {
            for (_, conts) in pendingAppliedContinuations {
                for cont in conts { cont.resume(throwing: error) }
            }
            pendingAppliedContinuations.removeAll()
            for (_, conts) in pendingUnsubscribeContinuations {
                for cont in conts { cont.resume(throwing: error) }
            }
            pendingUnsubscribeContinuations.removeAll()
        }
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
        _ = reason  // currently unused; kept for future logging
    }
}
