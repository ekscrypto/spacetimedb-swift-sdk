//
//  SpacetimeDBClient.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-09.
//

import Foundation

public actor SpacetimeDBClient {
    open class SocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
        internal var dbClient: SpacetimeDBClient?

        override init() {
            super.init()
        }

        public func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didOpenWithProtocol `protocol`: String?
        ) {
            Task.detached(priority: .utility) { [dbClient, webSocketTask] in
                guard let dbClient else {
                    webSocketTask.cancel()
                    return
                }
                await dbClient.connected()
            }
        }

        public func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
            reason: Data?
        ) {
            Task.detached(priority: .utility) { [dbClient] in
                await dbClient?.disconnected()
            }
//            print("WebSocket closed with code: \(closeCode), reason: \(String(describing: reason))")
//
//            if let reasonData = reason,
//               let reasonString = String(data: reasonData, encoding: .utf8) {
//                onError?("WebSocket closed: \(reasonString)")
//            }
        }

        public func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            Task.detached(priority: .utility) { [dbClient] in
                await dbClient?.disconnected()
            }
//
//            if let error = error {
//                print("WebSocket task completed with error: \(error)")
//                connectionStatus = "Error"
//                isConnecting = false
//                DispatchQueue.main.async {
//                    self.onError?("Connection error: \(error.localizedDescription)")
//                }
//            }
        }
    }

    func connected() async {
        guard let connectionId, let onConnect else { return }
        await onConnect(connectionId)
    }

    func disconnected() async {
        webSocketTask?.cancel()
        webSocketTask = nil
        connectionId = nil
        onConnect = nil

        guard let onError else { return }
        self.onError = nil

        await onError(Errors.disconnected)
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var delegate: SocketDelegate?
    private var connectionId: ConnectionId?
    private let urlSession: URLSession
    public let host: String
    public let dbName: String
    private var onError: ((Error) async -> Void)?
    private var onConnect: ((ConnectionId) async -> Void)?

    public enum Errors: Error {
        case incompatibleUrlSessionDelegate
        case alreadyConnected
        case failedToCreateSocketTask
        case disconnected
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
        db dbName: String,
        urlSession: URLSession? = nil
    ) throws {
        self.host = host
        self.dbName = dbName
        if let urlSession {
            guard let delegate = urlSession.delegate as? SocketDelegate else {
                throw Errors.incompatibleUrlSessionDelegate
            }
            self.urlSession = urlSession
            self.delegate = delegate
        } else {
            self.delegate = SocketDelegate()
            self.urlSession = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        }
    }

    private var uniqueSocketKey: String {
        let activeSocketKeyBytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return Data(activeSocketKeyBytes).base64EncodedString()
    }

    public func connect(
        token: AuthenticationToken? = nil,
        connectionId: ConnectionId = ConnectionId(),
        timeout: TimeInterval = 5.0,
        onError: @escaping (Error) async -> Void = { _ in },
        onConnect: @escaping (ConnectionId) async -> Void = { _ in }
    ) throws {
        guard webSocketTask == nil else {
            throw Errors.alreadyConnected
        }

        self.onError = onError
        self.onConnect = onConnect

        let v1Url = URL(string: "\(host)/v1/database/\(dbName)/subscribe?connection_id=\(connectionId.hexRepresentation)")!
        var request = URLRequest(
            url: v1Url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeout
        )

        request.setValue("Sec-WebSocket-Key", forHTTPHeaderField: uniqueSocketKey)
        if let token {
            request.setValue(token.rawValue, forHTTPHeaderField: "Authorization")
        }

        let socketTask = urlSession.webSocketTask(with: v1Url, protocols: ["v1.json.spacetimedb"])
        socketTask.resume()
        webSocketTask = socketTask
        self.connectionId = connectionId
    }

    public func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionId = nil
    }
}
