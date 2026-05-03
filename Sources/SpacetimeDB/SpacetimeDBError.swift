//
//  SpacetimeDBError.swift
//  spacetimedb-swift-sdk
//

import Foundation
import BSATN

/// Unified, `Sendable` error type for the Swift SDK. Future-canonical home for
/// every error the SDK can throw: connection lifecycle, protocol/encoding,
/// reducer lifecycle, subscription lifecycle.
///
/// During the transition the legacy `SpacetimeDBErrors` (plural),
/// `SpacetimeDBClient.Errors`, and `BSATNError` continue to be thrown from
/// existing call sites. New code should throw `SpacetimeDBError` directly;
/// the legacy types will be removed in a future major version.
public enum SpacetimeDBError: Error, Sendable, Equatable {

    // MARK: Connection lifecycle
    case notConnected
    case alreadyConnected
    case disconnected
    case timeout
    case invalidServerAddress
    case badServerResponse
    case incompatibleUrlSessionDelegate
    case failedToCreateSocketTask
    case unsupportedCompression(String)

    // MARK: Protocol / encoding
    /// A protocol message did not match its expected `ProductModel` shape.
    /// The associated `String` is the model's description for diagnostics.
    case invalidDefinition(String)
    /// A wrapped lower-level BSATN read/write error.
    case bsatn(BSATNError)
}

public extension SpacetimeDBError {
    /// Bridge a legacy `SpacetimeDBErrors` value into the unified type.
    init(_ legacy: SpacetimeDBErrors) {
        switch legacy {
        case .invalidDefinition(let model): self = .invalidDefinition(String(describing: model))
        case .notConnected: self = .notConnected
        case .timeout: self = .timeout
        }
    }

    /// Bridge a legacy `BSATNError` value into the unified type.
    init(_ bsatn: BSATNError) {
        self = .bsatn(bsatn)
    }
}
