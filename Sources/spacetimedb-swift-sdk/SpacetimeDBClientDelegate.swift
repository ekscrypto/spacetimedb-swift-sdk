//
//  SpacetimeDBClientDelegate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation

public protocol SpacetimeDBClientDelegate: AnyObject, Sendable {
    func onConnect(client: SpacetimeDBClient) async
    func onError(client: SpacetimeDBClient, error: any Error) async
    func onDisconnect(client: SpacetimeDBClient) async
    func onIncomingMessage(client: SpacetimeDBClient, message: Data) async
    func onSubscribeMultiApplied(client: SpacetimeDBClient, queryId: UInt32)
    func onIdentityReceived(client: SpacetimeDBClient, token: String, identity: String) async
    
    // Table update callbacks
    func onRowsInserted(client: SpacetimeDBClient, table: String, rows: [Any]) async
    func onRowsDeleted(client: SpacetimeDBClient, table: String, rows: [Any]) async
}
