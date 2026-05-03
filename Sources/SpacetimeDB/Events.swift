//
//  Events.swift
//  spacetimedb-swift-sdk
//

import Foundation
import BSATN

/// Connection-lifecycle event delivered on `SpacetimeDBClient.connectionEvents`.
public enum ConnectionEvent: Sendable {
    /// The server has accepted the connection and issued an `IdentityToken`.
    case connected(identity: Identity, connectionId: ConnectionId, token: String)
    /// Auto-reconnect is about to make another attempt (`attempt` starts at 1).
    case reconnecting(attempt: Int)
    /// Underlying transport closed. `reason` is the textual description of the
    /// triggering error, if any.
    case disconnected(reason: String?)
    /// Out-of-band error reported by the SDK (transport, decode, or protocol).
    case error(String)
}

/// Typed reducer-response event delivered on `SpacetimeDBClient.reducerEvents`.
public struct ReducerEvent: Sendable, Equatable {
    public let requestId: UInt32
    public let reducerName: String
    public let status: ReducerStatus
    public let energy: TransactionUpdate.EnergyQuanta

    public init(
        requestId: UInt32,
        reducerName: String,
        status: ReducerStatus,
        energy: TransactionUpdate.EnergyQuanta
    ) {
        self.requestId = requestId
        self.reducerName = reducerName
        self.status = status
        self.energy = energy
    }
}

/// Per-table batched update event delivered on
/// `SpacetimeDBClient.tableEvents(named:)`. Mirrors the legacy
/// `onTableUpdate` delegate payload — `[Any]` rows are produced by the
/// registered `TableRowDecoder`.
///
/// Marked `@unchecked Sendable` because decoded rows are typically immutable
/// value types produced by BSATN deserialization. Phase 6 will introduce a
/// strongly typed `RowEvent<T>` with primary-key-based update detection.
public struct TableEvent: @unchecked Sendable {
    public let tableName: String
    public let deletes: [Any]
    public let inserts: [Any]

    public init(tableName: String, deletes: [Any], inserts: [Any]) {
        self.tableName = tableName
        self.deletes = deletes
        self.inserts = inserts
    }
}

/// Subscription-lifecycle event delivered on
/// `SpacetimeDBClient.subscriptionEvents`.
public enum SubscriptionLifecycleEvent: Sendable, Equatable {
    case applied(queryId: UInt32, multi: Bool)
    case unsubscribed(queryId: UInt32, multi: Bool)
    case error(queryId: UInt32?, tableId: UInt32?, message: String)
}

/// Per-row event delivered on `SpacetimeDBClient.rowEvents(table:)`.
/// When the table's row type conforms to `BSATNTableWithPrimaryKey`,
/// delete+insert pairs sharing a PK within a single transaction are
/// merged into `.updated(old:new:)` events; otherwise only `.inserted`
/// and `.deleted` are emitted.
///
/// Marked `@unchecked Sendable` for the same reason as `TableEvent` —
/// decoded rows are typically immutable value types.
public enum RowEvent: @unchecked Sendable {
    case inserted(Any)
    case deleted(Any)
    case updated(old: Any, new: Any)

    public var tag: Tag {
        switch self {
        case .inserted: return .inserted
        case .deleted:  return .deleted
        case .updated:  return .updated
        }
    }

    public enum Tag: Sendable, Equatable { case inserted, deleted, updated }
}
