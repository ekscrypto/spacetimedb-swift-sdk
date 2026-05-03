//
//  DbConnectionBuilder.swift
//  spacetimedb-swift-sdk
//
//  TS v3-style fluent builder for `SpacetimeDBClient`.
//
//      let client = try SpacetimeDBClient.builder()
//          .withUri("https://maincloud.spacetimedb.com")
//          .withDatabaseName("quickstart-chat-55kji")
//          .withToken(token)
//          .withCompression(.brotli)
//          .withLightMode()
//          .build()
//
//  `SpacetimeDBClient.init(host:db:…)` and the builder produce the
//  same actor; the builder is pure ergonomics.
//

import Foundation
import BSATN

public struct DbConnectionBuilder: Sendable {

    public enum BuilderError: Error {
        /// `withUri(_:)` was not called.
        case missingUri
        /// `withDatabaseName(_:)` was not called.
        case missingDatabaseName
    }

    private var uri: String?
    private var dbName: String?
    private var token: AuthenticationToken?
    private var compression: Compression = .brotli
    private var confirmedReads: Bool = false
    private var lightMode: Bool = false
    private var debugEnabled: Bool = false
    private var enableAutoReconnect: Bool = true

    public init() {}

    public func withUri(_ uri: String) -> Self {
        var copy = self; copy.uri = uri; return copy
    }

    public func withDatabaseName(_ name: String) -> Self {
        var copy = self; copy.dbName = name; return copy
    }

    public func withToken(_ token: AuthenticationToken?) -> Self {
        var copy = self; copy.token = token; return copy
    }

    public func withCompression(_ compression: Compression) -> Self {
        var copy = self; copy.compression = compression; return copy
    }

    public func withConfirmedReads(_ enabled: Bool = true) -> Self {
        var copy = self; copy.confirmedReads = enabled; return copy
    }

    /// Enable light mode: every `callReducer` flips the
    /// `CallReducerFlags.noSuccessNotify` bit so the server doesn't
    /// echo a `TransactionUpdate` back to this client on success.
    public func withLightMode(_ enabled: Bool = true) -> Self {
        var copy = self; copy.lightMode = enabled; return copy
    }

    public func withDebug(_ enabled: Bool = true) -> Self {
        var copy = self; copy.debugEnabled = enabled; return copy
    }

    public func withAutoReconnect(_ enabled: Bool) -> Self {
        var copy = self; copy.enableAutoReconnect = enabled; return copy
    }

    /// Build the configured `SpacetimeDBClient`. Synchronous: no
    /// network traffic happens until `connect()` is called.
    public func build() throws -> SpacetimeDBClient {
        guard let uri else { throw BuilderError.missingUri }
        guard let dbName else { throw BuilderError.missingDatabaseName }
        return try SpacetimeDBClient(
            host: uri,
            db: dbName,
            compression: compression,
            confirmedReads: confirmedReads,
            lightMode: lightMode,
            debugEnabled: debugEnabled
        )
    }

    /// Build the client and `connect()` in one call. Returns the
    /// connected client (the WebSocket handshake has begun; await
    /// `client.connectionEvents` for the `.connected` event).
    public func buildAndConnect() async throws -> SpacetimeDBClient {
        let client = try build()
        try await client.connect(token: token, enableAutoReconnect: enableAutoReconnect)
        return client
    }

    // MARK: Test introspection

    internal var debugConfiguration: ResolvedConfiguration {
        ResolvedConfiguration(
            uri: uri,
            dbName: dbName,
            token: token,
            compression: compression,
            confirmedReads: confirmedReads,
            lightMode: lightMode,
            debugEnabled: debugEnabled,
            enableAutoReconnect: enableAutoReconnect
        )
    }

    internal struct ResolvedConfiguration: Sendable {
        let uri: String?
        let dbName: String?
        let token: AuthenticationToken?
        let compression: Compression
        let confirmedReads: Bool
        let lightMode: Bool
        let debugEnabled: Bool
        let enableAutoReconnect: Bool
    }
}

public extension SpacetimeDBClient {
    /// Entry point for the fluent builder. Equivalent to constructing
    /// a fresh `DbConnectionBuilder()`.
    static func builder() -> DbConnectionBuilder { DbConnectionBuilder() }
}
