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
        timeout: TimeInterval = 5.0,
        delegate clientDelegate: SpacetimeDBClientDelegate
    ) throws {
        guard webSocketTask == nil else {
            throw Errors.alreadyConnected
        }
        guard let socketDelegate = urlSession.delegate as? WebsocketDelegate else {
            throw Errors.incompatibleUrlSessionDelegate
        }
        socketDelegate.dbClient = self
        self.clientDelegate = clientDelegate
        self.socketDelegate = socketDelegate

        let v1Url = URL(string: "\(host)/v1/database/\(dbName)/subscribe?compression=\(compression.rawValue)")!
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
