//
//  SpacetimeDBClient.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-09.
//

import Foundation

public actor SpacetimeDBClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession
    public let host: String
    public let dbName: String

    public enum Errors: Error {
        case alreadyConnected
    }

    private var nextRequestId: UInt64 {
        _nextRequestId += 1
        return _nextRequestId
    }
    private var _nextRequestId: UInt64 = 0

    /// Returns a non-connected instance of the SpacetimeDBClient
    ///
    /// Parameters:
    /// - host: URL to the server root address including port number. I.e.: http://localhost:3000
    /// - dbName: Database name to which to connect. I.e.: "quickstart-chat"
    /// - urlSession: URLSession to use, will use .shared session by default
    ///
    public init(
        host: String,
        dbName: String,
        urlSession: URLSession = .shared
    ) {
        self.host = host
        self.dbName = dbName
        self.urlSession = urlSession
    }

    public func connect(
        token: AuthenticationToken?,
        connectionId: ConnectionId = ConnectionId()
    ) throws -> ConnectionId {
        guard webSocketTask == nil else {
            throw Errors.alreadyConnected
        }

        let v1Url = URL(string: "\(host)/v1/database/\(dbName)/subscribe?connection_id=\(connectionId.hexRepresentation)")!
        let socketTask = urlSession.webSocketTask(with: <#T##URL#>, protocols: <#T##[String]#>)
        return connectionId
    }
}
