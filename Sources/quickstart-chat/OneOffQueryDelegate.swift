//
//  OneOffQueryDelegate.swift
//  spacetimedb-swift-sdk
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

    func onIdentityReceived(client: SpacetimeDBClient, token: String, identity: UInt256) async {
        print("🆔 Identity received: \(identity.description.prefix(8))...")
        identityReceived = true
        checkReadyAndResume()
    }
}
