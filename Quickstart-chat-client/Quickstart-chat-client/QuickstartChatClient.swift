//
//  QuickstartChatClient.swift
//  Quickstart-chat-client
//
//  Created by Dave Poirier on 2025-08-09.
//

import Foundation
import spacetimedb_swift_sdk

actor QuickstartChat {

    private let spacetimeClient: SpacetimeDBClient!

    init(
        host: String = "http://localhost:3000",
        db: String = "quickstart-chat"
    ) throws {
        spacetimeClient = try SpacetimeDBClient(
            host: host,
            db: db
        )
    }

    func connect() async throws {
        try await spacetimeClient.connect(
            onError: { [weak self] error in await self?.onError(error) },
            onConnect: { [weak self] connectionId in await self?.onConnect(connectionId) }
        )
    }

    func onConnect(_ connectionId: ConnectionId) {
        print("Connected using \(connectionId)")
    }

    func onError(_ error: any Error) {
        print("Error: \(error)")
    }
}
