//
//  SpacetimeDBClient.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-09.
//

import Foundation
import BSATN

public actor SpacetimeDBClient {

    public enum Errors: Error {
        case incompatibleUrlSessionDelegate
        case alreadyConnected
        case failedToCreateSocketTask
        case disconnected
        case invalidServerAddress
        case badServerResponse
        case unsupportedCompression(String)
    }


    /// Returns a non-connected instance of the SpacetimeDBClient
    ///
    /// Parameters:
    /// - host: URL to the server root address including port number.
    ///   Accepts http://, https://, ws://, or wss:// schemes
    ///   (e.g. http://localhost:3000, https://maincloud.spacetimedb.com).
    /// - dbName: Database name to which to connect. I.e.: "quickstart-chat"
    /// - urlSession: URLSession to use, will use .shared session by default
    ///
    public init(
        host: String,
        db dbName: String,
        urlSession: URLSession? = nil,
        compression: Compression = .brotli,
        confirmedReads: Bool = false,
        lightMode: Bool = false,
        debugEnabled: Bool = false
    ) throws {
        self.confirmedReads = confirmedReads
        self.lightMode = lightMode
        let trimmed = host.hasSuffix("/") ? String(host.dropLast()) : host
        guard trimmed.hasPrefix("http://")
                || trimmed.hasPrefix("https://")
                || trimmed.hasPrefix("ws://")
                || trimmed.hasPrefix("wss://")
        else {
            throw Errors.invalidServerAddress
        }
        self.host = trimmed
        self.dbName = dbName
        self.compression = compression
        self.debugEnabled = debugEnabled
        // Set global debug configuration
        DebugConfiguration.shared.setEnabled(debugEnabled)
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
    internal let compression: Compression
    /// When `true`, the WebSocket subscribe URL gets `with_confirmed_reads=true`,
    /// instructing the server to wait for durable confirmation before returning
    /// query results. Trades latency for stronger consistency.
    internal let confirmedReads: Bool
    /// When `true`, every `callReducer` defaults to the
    /// `CallReducerFlags.noSuccessNotify` flag — on success the server
    /// suppresses the `TransactionUpdate` echo back to this client,
    /// which is how the TS v3 SDK exposes "light mode". Other clients'
    /// subscriptions still see the diffs.
    public let lightMode: Bool
    public let host: String
    public let dbName: String

    /// Host normalized to an http:// or https:// scheme (for REST endpoints).
    internal var httpHost: String {
        if host.hasPrefix("ws://") {
            return "http://" + host.dropFirst("ws://".count)
        }
        if host.hasPrefix("wss://") {
            return "https://" + host.dropFirst("wss://".count)
        }
        return host
    }

    /// Host normalized to a ws:// or wss:// scheme (for WebSocket endpoints).
    internal var wsHost: String {
        if host.hasPrefix("http://") {
            return "ws://" + host.dropFirst("http://".count)
        }
        if host.hasPrefix("https://") {
            return "wss://" + host.dropFirst("https://".count)
        }
        return host
    }
    public let debugEnabled: Bool
    internal var receiveTask: Task<Void, Error>?
    internal weak var clientDelegate: SpacetimeDBClientDelegate?

    public var connected: Bool { _connected }
    internal var _connected: Bool = false
    internal var currentIdentity: UInt256?
    internal var currentConnectionId: ConnectionId?

    /// Server-assigned identity for this client. `nil` until the
    /// `IdentityToken` message has been received post-connect.
    public var identity: Identity? {
        currentIdentity.map(Identity.init)
    }

    /// Per-WebSocket-session connection identifier. `nil` until the
    /// `IdentityToken` message has been received post-connect.
    public var connectionId: ConnectionId? {
        currentConnectionId
    }

    // Reconnection properties
    internal var shouldReconnect: Bool = false
    internal var isReconnecting: Bool = false
    internal var reconnectAttempts: Int = 0
    internal var maxReconnectAttempts: Int = 10
    internal var reconnectTask: Task<Void, Never>?
    internal var lastToken: AuthenticationToken?

    internal var nextRequestId: UInt32 {
        _nextRequestId += 1
        return _nextRequestId
    }
    private var _nextRequestId: UInt32 = 0

    public var nextQueryId: UInt32 {
        _nextQueryId += 1
        return _nextQueryId
    }
    private var _nextQueryId: UInt32 = 0

    internal var uniqueSocketKey: String {
        let activeSocketKeyBytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return Data(activeSocketKeyBytes).base64EncodedString()
    }

    // Table Row Decoders
    private var tableRowDecoders: [String: TableRowDecoder] = [:]

    // OneOffQuery Management — keyed by request_id (v2). Resolves with the
    // wire-level message; the public API in `+oneOffQuery.swift` adapts it.
    internal var pendingOneOffQueries: [UInt32: CheckedContinuation<OneOffQueryResultMessage, Error>] = [:]

    // Pending callReducer continuations, keyed by request_id. Reducers are
    // correlated by name (the server does not echo the name in `ReducerResult`),
    // so we stash the name here to enrich `ReducerEvent`s.
    internal var pendingReducerCalls: [UInt32: PendingReducerCall] = [:]
    // Pending callProcedure continuations, keyed by request_id.
    internal var pendingProcedureCalls: [UInt32: PendingProcedureCall] = [:]

    internal struct PendingReducerCall {
        let reducerName: String
        let continuation: CheckedContinuation<ReducerSuccess, Error>
    }
    internal struct PendingProcedureCall {
        let procedureName: String
        let continuation: CheckedContinuation<Data, Error>
    }

    // AsyncStream continuation registries (one bucket per channel).
    internal var connectionContinuations: [UUID: AsyncStream<ConnectionEvent>.Continuation] = [:]
    internal var reducerContinuations: [UUID: AsyncStream<ReducerEvent>.Continuation] = [:]
    internal var subscriptionContinuations: [UUID: AsyncStream<SubscriptionLifecycleEvent>.Continuation] = [:]
    internal var tableContinuations: [String: [UUID: AsyncStream<TableEvent>.Continuation]] = [:]
    internal var rowContinuations: [String: [UUID: AsyncStream<RowEvent>.Continuation]] = [:]
    // Foreign-client transaction events.
    internal var transactionContinuations: [UUID: AsyncStream<TransactionEvent>.Continuation] = [:]

    // Pending-future registries for SubscriptionHandle.applied()/unsubscribe().
    internal var pendingAppliedContinuations: [UInt32: [CheckedContinuation<Void, Error>]] = [:]
    internal var pendingUnsubscribeContinuations: [UInt32: [CheckedContinuation<Void, Error>]] = [:]

    public func registerTableRowDecoder(table: String, decoder: TableRowDecoder) {
        tableRowDecoders[table] = decoder
    }

    public func decoder(forTable name: String) -> TableRowDecoder? {
        return tableRowDecoders[name]
    }

    /// Names of every table for which a row decoder is currently
    /// registered. Used by `subscribeToAllTables()`.
    public func registeredTableNames() -> [String] {
        Array(tableRowDecoders.keys)
    }

    // MARK: - Reconnection Logic

    internal func startReconnection() {
        guard shouldReconnect && !isReconnecting else { return }

        isReconnecting = true
        reconnectTask?.cancel()

        reconnectTask = Task { [weak self] in
            guard let self = self else { return }

            while true {
                let shouldContinue = await self.shouldReconnect
                let attempts = await self.reconnectAttempts
                let maxAttempts = await self.maxReconnectAttempts

                guard shouldContinue && attempts < maxAttempts else { break }

                let attempt = attempts + 1
                await self.setReconnectAttempts(attempt)

                // Notify delegate about reconnection attempt
                await self.clientDelegate?.onReconnecting(client: self, attempt: attempt)
                await self.emit(connection: .reconnecting(attempt: attempt))

                // Calculate backoff delay (exponential with jitter)
                let baseDelay = min(pow(2.0, Double(attempt - 1)), 30.0) // Cap at 30 seconds
                let jitter = Double.random(in: 0...1)
                let delay = baseDelay + jitter

                debugLog(">>> Reconnection attempt \(attempt) in \(String(format: "%.1f", delay)) seconds")

                // Wait before attempting reconnection
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                // Check if we should still reconnect
                guard await self.shouldReconnect else { break }

                do {
                    // Attempt to reconnect
                    if let delegate = await self.clientDelegate {
                        try await self.connect(
                            token: await self.lastToken,
                            timeout: 10.0,
                            delegate: delegate,
                            enableAutoReconnect: true
                        )
                        // The WS handshake succeeded, but a stable session
                        // is only confirmed when the server sends IdentityToken.
                        // The attempt counter is reset there.
                        await self.setIsReconnecting(false)
                        break
                    }
                } catch {
                    debugLog(">>> Reconnection attempt \(attempt) failed: \(error)")
                    // Continue to next attempt
                }
            }

            await self.setIsReconnecting(false)

            let finalAttempts = await self.reconnectAttempts
            let maxAttempts = await self.maxReconnectAttempts

            if finalAttempts >= maxAttempts {
                debugLog(">>> Max reconnection attempts reached")
                await self.clientDelegate?.onError(client: self, error: Errors.disconnected)
                await self.emit(connection: .error("Max reconnection attempts reached"))
            }
        }
    }

    public func stopAutoReconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    // Helper methods for actor isolation
    private func setReconnectAttempts(_ value: Int) {
        reconnectAttempts = value
    }

    private func setIsReconnecting(_ value: Bool) {
        isReconnecting = value
    }
}
