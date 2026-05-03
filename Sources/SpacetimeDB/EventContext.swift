//
//  EventContext.swift
//  spacetimedb-swift-sdk
//
//  Phase 13: TS v3-style event contexts. Every SDK callback that
//  surfaces row/reducer/subscription events can be paired with an
//  `EventContext` carrying:
//    - the live client (so the callback can issue further reducer or
//      procedure calls without capturing it),
//    - the user's typed `Db` (the codegen-emitted accessor),
//    - the user's typed `Reducers` view.
//
//  The SDK doesn't know what the codegen names those types, so
//  `EventContext` is generic over `Db` and `Reducers` and stays a
//  pure value type. Codegen wires it together by exposing context-
//  aware overloads on the emitted `Db` struct (see SwiftEmitter.swift).
//

import Foundation

public struct EventContext<Db: Sendable, Reducers: Sendable>: Sendable {
    /// The connection that produced this event. Use it for further
    /// reducer / procedure calls, or to access streams/state.
    public let client: SpacetimeDBClient
    /// Codegen-emitted typed table accessor.
    public let db: Db
    /// Codegen-emitted typed reducer accessor.
    public let reducers: Reducers

    public init(client: SpacetimeDBClient, db: Db, reducers: Reducers) {
        self.client = client
        self.db = db
        self.reducers = reducers
    }
}

/// Lightweight context for callbacks that don't need typed Db /
/// Reducers — it just exposes the client. Useful for SDK-internal
/// surfaces and for user code that prefers to capture state directly.
public struct ClientContext: Sendable {
    public let client: SpacetimeDBClient

    public init(client: SpacetimeDBClient) {
        self.client = client
    }
}
