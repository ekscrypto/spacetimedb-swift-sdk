//
//  Events.swift
//  spacetimedb-swift-sdk
//

import Foundation
import BSATN

/// Connection-lifecycle event delivered on `SpacetimeDBClient.connectionEvents`.
public enum ConnectionEvent: Sendable {
    /// Server accepted the connection and issued an `InitialConnection` message.
    case connected(identity: Identity, connectionId: ConnectionId, token: String)
    /// Auto-reconnect is about to make another attempt (`attempt` starts at 1).
    case reconnecting(attempt: Int)
    /// Underlying transport closed. `reason` is the textual description of the
    /// triggering error, if any.
    case disconnected(reason: String?)
    /// Out-of-band error reported by the SDK (transport, decode, or protocol).
    case error(String)
}

/// Reducer-completion event delivered on `SpacetimeDBClient.reducerEvents`.
/// Fires once per `ReducerResult` (i.e. per self-issued `callReducer` that
/// the server has responded to). Other clients' reducer activity is not
/// echoed in v2; the row diffs from external transactions arrive on the
/// per-table streams without reducer metadata.
public struct ReducerEvent: Sendable {
    public let requestId: UInt32
    public let reducerName: String
    public let timestamp: Date
    public let outcome: ReducerOutcome

    public init(requestId: UInt32, reducerName: String, timestamp: Date, outcome: ReducerOutcome) {
        self.requestId = requestId
        self.reducerName = reducerName
        self.timestamp = timestamp
        self.outcome = outcome
    }
}

/// Per-table batched update event delivered on
/// `SpacetimeDBClient.tableEvents(named:)`. `[Any]` rows are produced by
/// the registered `TableRowDecoder`.
///
/// Marked `@unchecked Sendable` because decoded rows are typically immutable
/// value types produced by BSATN deserialization.
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
    case applied(queryId: UInt32)
    case unsubscribed(queryId: UInt32)
    /// Server reported a subscription failure. `requestId` is set if the
    /// failure was the response to a client-issued Subscribe; nil if it
    /// arose mid-subscription (e.g. recompilation failure).
    case error(queryId: UInt32, requestId: UInt32?, message: String)
}

/// Per-row event delivered on `SpacetimeDBClient.rowEvents(table:)`.
/// When the table's row type conforms to `BSATNTableWithPrimaryKey`,
/// delete+insert pairs sharing a PK within a single transaction are
/// merged into `.updated(old:new:)` events; otherwise only `.inserted`
/// and `.deleted` are emitted.
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
