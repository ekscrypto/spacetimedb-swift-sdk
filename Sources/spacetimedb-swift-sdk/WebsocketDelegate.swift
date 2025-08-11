//
//  WebsocketDelegate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation

open class WebsocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    internal weak var dbClient: SpacetimeDBClient?

    override init() {
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol `protocol`: String?
    ) {
        guard let dbClient else {
            webSocketTask.cancel()
            return
        }
        Task.detached(priority: .utility) { [dbClient] in
            await dbClient.websocketConnected()
        }
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task.detached(priority: .utility) { [dbClient] in
            await dbClient?.websocketDisconnected()
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task.detached(priority: .utility) { [dbClient] in
            await dbClient?.websocketDisconnected()
        }
    }
}
