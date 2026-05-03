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
    /// `delegate` is optional now: applications using only the AsyncStream
    /// surface (`client.connectionEvents` / `.reducerEvents` / `.tableEvents`
    /// / `.rowEvents`) and `SubscriptionHandle` should pass `nil`. The
    /// legacy `SpacetimeDBClientDelegate` still works for backward compat.
    public func connect(
        token: AuthenticationToken? = nil,
        timeout: TimeInterval = 10.0,
        delegate clientDelegate: SpacetimeDBClientDelegate? = nil,
        enableAutoReconnect: Bool = true
    ) throws {
        guard webSocketTask == nil else {
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

        guard let socketDelegate = urlSession.delegate as? WebsocketDelegate else {
            throw Errors.incompatibleUrlSessionDelegate
        }
        socketDelegate.dbClient = self
        self.clientDelegate = clientDelegate
        self.socketDelegate = socketDelegate

        var urlString = "\(wsHost)/v1/database/\(dbName)/subscribe?compression=\(compression.serverString)"
        if confirmedReads {
            urlString += "&confirmed=true"
        }
        guard let url = URL(string: urlString) else {
            throw Errors.invalidServerAddress
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeout
        )

        request.setValue(uniqueSocketKey, forHTTPHeaderField: "Sec-WebSocket-Key")
        request.setValue("v2.bsatn.spacetimedb", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        if let token {
            request.setValue("Bearer \(token.rawValue)", forHTTPHeaderField: "Authorization")
        }

        let socketTask = urlSession.webSocketTask(with: request)
        webSocketTask = socketTask
        socketTask.resume()
        receiveTask = Task(priority: .utility) {
            try await self.receiveMessage()
        }
    }

}
