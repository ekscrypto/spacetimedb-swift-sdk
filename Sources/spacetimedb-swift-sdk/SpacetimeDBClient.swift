//
//  SpacetimeDBClient.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-09.
//

import Foundation

public actor SpacetimeDBClient {

    public enum Errors: Error {
        case incompatibleUrlSessionDelegate
        case alreadyConnected
        case failedToCreateSocketTask
        case disconnected
        case invalidServerAddress
        case badServerResponse
    }

    /// Returns a non-connected instance of the SpacetimeDBClient
    ///
    /// Parameters:
    /// - host: URL to the server root address including port number. I.e.: http://localhost:3000
    /// - dbName: Database name to which to connect. I.e.: "quickstart-chat"
    /// - urlSession: URLSession to use, will use .shared session by default
    ///
    public init(
        host: String,
        db dbName: String,
        urlSession: URLSession? = nil
    ) throws {
        self.host = host
        self.dbName = dbName
        if let urlSession {
            guard let delegate = urlSession.delegate as? WebsocketDelegate else {
                throw Errors.incompatibleUrlSessionDelegate
            }
            self.urlSession = urlSession
            self.socketDelegate = delegate
        } else {
            self.socketDelegate = WebsocketDelegate()
            self.urlSession = URLSession(configuration: .ephemeral, delegate: socketDelegate, delegateQueue: nil)
        }
    }

    internal var webSocketTask: URLSessionWebSocketTask?
    internal var socketDelegate: WebsocketDelegate?
    internal let urlSession: URLSession
    public let host: String
    public let dbName: String
    internal var receiveTask: Task<Void, Error>?
    internal weak var clientDelegate: SpacetimeDBClientDelegate?

    public var connected: Bool { _connected }
    internal var _connected: Bool = false

    internal var nextRequestId: UInt64 {
        _nextRequestId += 1
        return _nextRequestId
    }
    private var _nextRequestId: UInt64 = 0

    internal var uniqueSocketKey: String {
        let activeSocketKeyBytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return Data(activeSocketKeyBytes).base64EncodedString()
    }
}
