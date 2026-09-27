//
//  SpacetimeDBClient+connect.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation

extension SpacetimeDBClient {
    /// Connect to the server.
    ///
    /// `delegate` is optional: applications using only the AsyncStream
    /// surface (`client.connectionEvents` / `.reducerEvents` / `.tableEvents`
    /// / `.rowEvents`) and `SubscriptionHandle` should pass `nil`. Pass an
    /// instance of `SpacetimeDBClientDelegate` to receive callbacks instead.
    public func connect(
        token: AuthenticationToken? = nil,
        timeout: TimeInterval = 10.0,
        delegate clientDelegate: SpacetimeDBClientDelegate? = nil,
        enableAutoReconnect: Bool = true
    ) throws {
        guard wsConnection == nil else {
            throw Errors.alreadyConnected
        }

        // Store for reconnection
        self.lastToken = token
        self.shouldReconnect = enableAutoReconnect
        // Only reset the attempt counter for user-initiated connects.
        // Reconnect-loop iterations call back into connect() and must preserve
        // the running attempt count so the loop can give up after maxAttempts.
        if !isReconnecting {
            self.reconnectAttempts = 0
        }

        // All compression formats (none / brotli / gzip) are now supported
        // via the Compression framework on iOS 15+/macOS 12+ — see
        // CompressibleQueryUpdate.decompressGzip / decompressBrotli.

        self.clientDelegate = clientDelegate

        var urlString = "\(wsHost)/v1/database/\(dbName)/subscribe?compression=\(compression.serverString)"
        if confirmedReads {
            urlString += "&confirmed=true"
        }
        guard let url = URL(string: urlString) else {
            throw Errors.invalidServerAddress
        }

        var headers: [(name: String, value: String)] = []
        if let token {
            headers.append((name: "Authorization", value: "Bearer \(token.rawValue)"))
        }

        let connection = NWWebSocketConnection(
            url: url,
            headers: headers,
            subprotocol: "v2.bsatn.spacetimedb"
        )
        connection.onEvent { [weak self] event in
            guard let self else { return }
            Task { await self.handleTransportEvent(event) }
        }
        wsConnection = connection
        connection.open(timeout: timeout)
        receiveTask = Task(priority: .utility) {
            try await self.receiveMessage()
        }
    }

}
