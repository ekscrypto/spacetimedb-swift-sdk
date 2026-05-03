//
//  SpacetimeDBClient+connect.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation

extension SpacetimeDBClient {
    /// Connect to the server
    public func connect(
        token: AuthenticationToken? = nil,
        timeout: TimeInterval = 10.0,
        delegate clientDelegate: SpacetimeDBClientDelegate,
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

        // Validate compression support before attempting connection
        switch compression {
        case .none:
            // Always supported
            break
        case .gzip:
            // Gzip is not currently supported
            throw Errors.unsupportedCompression("Gzip compression is not currently supported")
        case .brotli:
            // Brotli requires iOS 15+/macOS 12+ via Compression framework
            // Our minimum targets support this
            break
        }

        guard let socketDelegate = urlSession.delegate as? WebsocketDelegate else {
            throw Errors.incompatibleUrlSessionDelegate
        }
        socketDelegate.dbClient = self
        self.clientDelegate = clientDelegate
        self.socketDelegate = socketDelegate

        guard let v1Url = URL(string: "\(wsHost)/v1/database/\(dbName)/subscribe?compression=\(compression.serverString)") else {
            throw Errors.invalidServerAddress
        }
        var request = URLRequest(
            url: v1Url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeout
        )

        request.setValue(uniqueSocketKey, forHTTPHeaderField: "Sec-WebSocket-Key")
        request.setValue("v1.bsatn.spacetimedb", forHTTPHeaderField: "Sec-WebSocket-Protocol")
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
