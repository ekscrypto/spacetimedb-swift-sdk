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

    public enum Compression: String {
        case none = "None"
        case brotli = "Brotli"
        case gzip = "Gzip"
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
        urlSession: URLSession? = nil,
        compression: Compression = .brotli,
        debugEnabled: Bool = false
    ) throws {
        // Check for unsupported compression
        if compression == .gzip {
            throw Errors.unsupportedCompression("Gzip compression is not currently supported")
        }
        
        self.host = host
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
    public let host: String
    public let dbName: String
    public let debugEnabled: Bool
    internal var receiveTask: Task<Void, Error>?
    internal weak var clientDelegate: SpacetimeDBClientDelegate?

    public var connected: Bool { _connected }
    internal var _connected: Bool = false
    internal var currentIdentity: UInt256?
    
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

    internal var uniqueSocketKey: String {
        let activeSocketKeyBytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return Data(activeSocketKeyBytes).base64EncodedString()
    }
    
    // Table Row Decoders
    private var tableRowDecoders: [String: TableRowDecoder] = [:]
    
    public func registerTableRowDecoder(table: String, decoder: TableRowDecoder) {
        tableRowDecoders[table] = decoder
    }
    
    internal func decoder(forTable name: String) -> TableRowDecoder? {
        return tableRowDecoders[name]
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
                        // If successful, reset attempts
                        await self.setReconnectAttempts(0)
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
