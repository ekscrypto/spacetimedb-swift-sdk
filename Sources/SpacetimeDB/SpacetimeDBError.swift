//
//  SpacetimeDBError.swift
//  spacetimedb-swift-sdk
//

import Foundation
import BSATN

/// Unified, `Sendable` error type for the Swift SDK. Covers connection
/// lifecycle, protocol/encoding, reducer lifecycle, and subscription
/// lifecycle errors.
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
    /// Wrap a `SpacetimeDBErrors` value into the unified type.
    init(_ source: SpacetimeDBErrors) {
        switch source {
        case .invalidDefinition(let model): self = .invalidDefinition(String(describing: model))
        case .notConnected: self = .notConnected
        case .timeout: self = .timeout
        }
    }

    /// Wrap a `BSATNError` value into the unified type.
    init(_ bsatn: BSATNError) {
        self = .bsatn(bsatn)
    }
}
