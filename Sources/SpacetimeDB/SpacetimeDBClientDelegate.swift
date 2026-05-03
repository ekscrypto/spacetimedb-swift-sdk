//
//  SpacetimeDBClientDelegate.swift
//  spacetimedb-swift-sdk
//
//  Delegate-style notification surface. Application code may adopt this
//  protocol or use the AsyncStream API on `SpacetimeDBClient`
//  (`connectionEvents`, `reducerEvents`, `subscriptionEvents`,
//  `tableEvents(named:)`, `rowEvents(table:)`); both fan out from the
//  same receive loop.
//
//  All methods are optional via the protocol-extension defaults below.
//

import Foundation
import BSATN

public protocol SpacetimeDBClientDelegate: AnyObject, Sendable {
    func onConnect(client: SpacetimeDBClient) async
    func onError(client: SpacetimeDBClient, error: any Error) async
    func onDisconnect(client: SpacetimeDBClient) async
    func onReconnecting(client: SpacetimeDBClient, attempt: Int) async
    func onIncomingMessage(client: SpacetimeDBClient, message: Data) async
    func onIdentityReceived(client: SpacetimeDBClient, token: String, identity: BSATN.UInt256) async

    /// Server confirmed a Subscribe message.
    func onSubscribeApplied(client: SpacetimeDBClient, queryId: UInt32) async
    /// Server confirmed an Unsubscribe message.
    func onUnsubscribeApplied(client: SpacetimeDBClient, queryId: UInt32) async
    /// Server reported a subscription-lifecycle error.
    func onSubscriptionError(client: SpacetimeDBClient, queryId: UInt32, requestId: UInt32?, error: String) async

    /// Per-table batched row diffs for one transaction. Decoded rows are
    /// produced by the registered `TableRowDecoder`; if no decoder is
    /// registered for the table, the arrays carry raw `Data` rows.
    func onTableUpdate(client: SpacetimeDBClient, event: TableEvent) async

    /// Server response to a `callReducer`. The full outcome enum is
    /// passed; consumers can pattern-match on `.ok` / `.okEmpty` /
    /// `.error` / `.internalError`.
    func onReducerResponse(client: SpacetimeDBClient, requestId: UInt32, reducerName: String, outcome: ReducerOutcome) async

    /// Server response to a `callProcedure`.
    func onProcedureResponse(client: SpacetimeDBClient, requestId: UInt32, procedureName: String, status: ProcedureStatus) async
}

public extension SpacetimeDBClientDelegate {
    func onConnect(client: SpacetimeDBClient) async {}
    func onError(client: SpacetimeDBClient, error: any Error) async {}
    func onDisconnect(client: SpacetimeDBClient) async {}
    func onReconnecting(client: SpacetimeDBClient, attempt: Int) async {}
    func onIncomingMessage(client: SpacetimeDBClient, message: Data) async {}
    func onIdentityReceived(client: SpacetimeDBClient, token: String, identity: BSATN.UInt256) async {}
    func onSubscribeApplied(client: SpacetimeDBClient, queryId: UInt32) async {}
    func onUnsubscribeApplied(client: SpacetimeDBClient, queryId: UInt32) async {}
    func onSubscriptionError(client: SpacetimeDBClient, queryId: UInt32, requestId: UInt32?, error: String) async {}
    func onTableUpdate(client: SpacetimeDBClient, event: TableEvent) async {}
    func onReducerResponse(client: SpacetimeDBClient, requestId: UInt32, reducerName: String, outcome: ReducerOutcome) async {}
    func onProcedureResponse(client: SpacetimeDBClient, requestId: UInt32, procedureName: String, status: ProcedureStatus) async {}
}
