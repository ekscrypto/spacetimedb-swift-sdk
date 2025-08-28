//
//  OneOffQueryDelegate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-28.
//

import Foundation
import SpacetimeDB
import BSATN

actor OneOffQueryDelegate: SpacetimeDBClientDelegate {
    private var connectionContinuation: CheckedContinuation<Void, Never>?
    private var identityReceived = false
    private var connected = false
    
    func waitForConnection() async {
        await withCheckedContinuation { continuation in
            self.connectionContinuation = continuation
        }
    }
    
    private func checkReadyAndResume() {
        if connected && identityReceived, let continuation = connectionContinuation {
            print("✅ Connection and identity ready for OneOffQuery")
            continuation.resume()
            connectionContinuation = nil
        }
    }
    
    func onConnect(client: SpacetimeDBClient) async {
        print("🔗 Connection established")
        connected = true
        checkReadyAndResume()
    }
    
    nonisolated func onDisconnect(client: SpacetimeDBClient) async {}
    func onIdentityReceived(client: SpacetimeDBClient, token: String, identity: UInt256) async {
        print("🆔 Identity received: \(identity.description.prefix(8))...")
        identityReceived = true
        checkReadyAndResume()
    }
    nonisolated func onSubscribeMultiApplied(client: SpacetimeDBClient, queryId: UInt32) {}
    nonisolated func onTableUpdate(client: SpacetimeDBClient, table: String, deletes: [Any], inserts: [Any]) async {}
    nonisolated func onReducerResponse(client: SpacetimeDBClient, reducer: String, requestId: UInt32, status: String, message: String?, energyUsed: UInt128) async {}
    nonisolated func onError(client: SpacetimeDBClient, error: Error) async {}
    nonisolated func onReconnecting(client: SpacetimeDBClient, attempt: Int) async {}
    nonisolated func onIncomingMessage(client: SpacetimeDBClient, message: Data) async {}
}