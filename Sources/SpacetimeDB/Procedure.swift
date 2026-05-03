//
//  Procedure.swift
//  spacetimedb-swift-sdk
//
//  Typed counterpart to `Reducer` for v2 procedure RPCs. A `Procedure`
//  wraps the wire-level `callProcedure(name:arguments:)` with typed
//  argument encoding and typed return-value decoding.
//

import Foundation
import BSATN

/// Protocol for defining procedures (non-transactional read-only RPCs)
/// that can be called on SpacetimeDB v2.
///
/// Mirrors `Reducer` but adds an associated `ReturnValue` type, since
/// procedures return BSATN-encoded data the caller usually wants
/// decoded. Use `VoidProcedure` for procedures with no arguments and
/// `RawProcedure` to pass through raw bytes.
public protocol Procedure {
    /// Decoded return type. Use `Void` (or `EmptyReturn`) for procedures
    /// that return no useful payload.
    associatedtype ReturnValue

    /// The name of the procedure as defined on the server.
    var name: String { get }

    /// Encode the procedure arguments to BSATN format.
    func encodeArguments(writer: BSATNWriter) throws

    /// Decode the BSATN-encoded return payload the server sent back.
    /// The default implementation handles `ReturnValue == Data` and
    /// `ReturnValue == Void`; override for typed payloads.
    func decodeReturnValue(_ data: Data) throws -> ReturnValue
}

public extension Procedure where ReturnValue == Data {
    /// Default for raw-bytes procedures: hand the payload to the caller
    /// untouched.
    func decodeReturnValue(_ data: Data) throws -> Data { data }
}

public extension Procedure where ReturnValue == Void {
    /// Default for procedures whose return value is ignored.
    func decodeReturnValue(_ data: Data) throws -> Void { () }
}

/// A procedure with no arguments returning raw bytes. Equivalent to
/// `VoidReducer` for the `Reducer` family.
public struct VoidProcedure: Procedure {
    public typealias ReturnValue = Data
    public let name: String

    public init(name: String) {
        self.name = name
    }

    public func encodeArguments(writer: BSATNWriter) throws {
        // No arguments to encode.
    }
}

/// Generic procedure that takes raw BSATN-encoded arguments and returns
/// the raw response payload. Equivalent to `RawReducer`.
public struct RawProcedure: Procedure {
    public typealias ReturnValue = Data
    public let name: String
    public let encodedArguments: Data

    public init(name: String, encodedArguments: Data = Data()) {
        self.name = name
        self.encodedArguments = encodedArguments
    }

    public func encodeArguments(writer: BSATNWriter) throws {
        writer.writeBytes(encodedArguments)
    }
}
