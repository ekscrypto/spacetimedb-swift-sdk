//
//  SpacetimeDBClientDelegate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation
import BSATN

public protocol SpacetimeDBClientDelegate: AnyObject, Sendable {
    func onConnect(client: SpacetimeDBClient) async
    func onError(client: SpacetimeDBClient, error: any Error) async
    func onDisconnect(client: SpacetimeDBClient) async
    func onReconnecting(client: SpacetimeDBClient, attempt: Int) async
    func onIncomingMessage(client: SpacetimeDBClient, message: Data) async
    func onSubscribeMultiApplied(client: SpacetimeDBClient, queryId: UInt32)
    func onSubscribeApplied(client: SpacetimeDBClient, queryId: UInt32)
    func onIdentityReceived(client: SpacetimeDBClient, token: String, identity: BSATN.UInt256) async

    // Called when a table has updates (deletes and/or inserts) in a single transaction
    // This allows the client to detect updates by comparing identities between deletes and inserts
    func onTableUpdate(client: SpacetimeDBClient, table: String, deletes: [Any], inserts: [Any]) async

    // Called when the SDK receives a response after reducer execution
    // The status indicates whether the reducer was committed, failed, or ran out of energy
    // energyUsed is the amount of energy consumed by the reducer execution
    //
    // Legacy string-status form. New code should override
    // `onReducerResponse(client:requestId:reducerName:status:energy:)` instead;
    // the SDK calls the typed form, whose default implementation bridges back
    // to this method for backward compatibility.
    func onReducerResponse(client: SpacetimeDBClient, reducer: String, requestId: UInt32, status: String, message: String?, energyUsed: UInt128) async

    // Typed reducer-response callback. Status is `ReducerStatus.committed`,
    // `.failed(String)`, or `.outOfEnergy`; energy carries both budget and used.
    func onReducerResponse(client: SpacetimeDBClient, requestId: UInt32, reducerName: String, status: ReducerStatus, energy: TransactionUpdate.EnergyQuanta) async

    // Called when a one-off query response is received
    func onOneOffQueryResponse(client: SpacetimeDBClient, result: OneOffQueryResult) async

    // Called when an unsubscribe request is confirmed
    func onUnsubscribeApplied(client: SpacetimeDBClient, queryId: UInt32) async

    // Called when the server reports a subscription-lifecycle error.
    // queryId/tableId may be nil — see SubscriptionErrorMessage for semantics.
    func onSubscriptionError(client: SpacetimeDBClient, queryId: UInt32?, tableId: UInt32?, error: String) async

    // Called for a TransactionUpdateLight — table diffs without reducer event metadata.
    // Per-table row diffs are still delivered via onTableUpdate.
    func onTransactionUpdateLight(client: SpacetimeDBClient, requestId: UInt32) async
}

// Default implementation for optional delegate methods
public extension SpacetimeDBClientDelegate {
    func onOneOffQueryResponse(client: SpacetimeDBClient, result: OneOffQueryResult) async {
        // Default empty implementation
    }

    func onUnsubscribeApplied(client: SpacetimeDBClient, queryId: UInt32) async {
        // Default empty implementation
    }

    func onSubscribeApplied(client: SpacetimeDBClient, queryId: UInt32) {
        // Default empty implementation
    }

    func onSubscriptionError(client: SpacetimeDBClient, queryId: UInt32?, tableId: UInt32?, error: String) async {
        // Default empty implementation
    }

    func onTransactionUpdateLight(client: SpacetimeDBClient, requestId: UInt32) async {
        // Default empty implementation
    }

    // Typed callback default — bridges to the legacy string-status form so
    // existing delegates that only override the legacy method continue to
    // receive reducer responses unchanged.
    func onReducerResponse(client: SpacetimeDBClient, requestId: UInt32, reducerName: String, status: ReducerStatus, energy: TransactionUpdate.EnergyQuanta) async {
        let legacyStatus: String
        let message: String?
        switch status {
        case .committed:
            legacyStatus = "committed"
            message = nil
        case .failed(let msg):
            legacyStatus = "failed: \(msg)"
            message = msg
        case .outOfEnergy:
            legacyStatus = "out of energy"
            message = nil
        }
        await onReducerResponse(
            client: client,
            reducer: reducerName,
            requestId: requestId,
            status: legacyStatus,
            message: message,
            energyUsed: energy.used
        )
    }
}
