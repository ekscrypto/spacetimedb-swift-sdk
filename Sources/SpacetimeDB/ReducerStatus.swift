//
//  ReducerStatus.swift
//  spacetimedb-swift-sdk
//

import Foundation

/// Outcome of a reducer invocation, as reported in `TransactionUpdate.status`.
/// Mirrors `spacetimedb_sdk::Status` in the reference Rust SDK.
///
/// The committed-payload `DatabaseUpdate` is intentionally *not* included
/// here — it is delivered through `onTableUpdate` and (in later phases) the
/// per-table row event streams. `ReducerStatus` is the typed answer to
/// "did this reducer succeed?".
public enum ReducerStatus: Sendable, Equatable {
    case committed
    case failed(String)
    case outOfEnergy

    public var isCommitted: Bool {
        if case .committed = self { return true }
        return false
    }

    public var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}
