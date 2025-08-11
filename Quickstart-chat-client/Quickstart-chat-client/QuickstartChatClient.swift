//
//  QuickstartChatClient.swift
//  Quickstart-chat-client
//
//  Created by Dave Poirier on 2025-08-09.
//

import Foundation
import spacetimedb_swift_sdk

actor QuickstartChat: SpacetimeDBClientDelegate {
    private let spacetimeClient: SpacetimeDBClient!
    private var identity: Identity?
    private var token: AuthenticationToken?
    private var connected: Bool = false

    init(
        host: String = "ws://localhost:3000",
        db: String = "quickstart-chat"
    ) throws {
        spacetimeClient = try SpacetimeDBClient(
            host: host,
            db: db
        )
    }

    func retrieveNewIdentity() async throws {
        let (identity, token) = try await spacetimeClient.identity()
        self.identity = identity
        self.token = token
    }

    func connect() async throws {
        try await spacetimeClient.connect(
            token: token,
            delegate: self
        )
    }

    func onConnect() {
        print("Connected!")
        connected = true
    }

    func onDisconnect() async {
        print("Disconnected")
    }

    func onError(_ error: any Error) {
        print("Error: \(error)")
        connected = false
    }

    func onIncomingMessage(_ data: Data) {
        guard let message = String(data: data, encoding: .utf8) else { return }
        print("Received message: \(message)")
    }
}
