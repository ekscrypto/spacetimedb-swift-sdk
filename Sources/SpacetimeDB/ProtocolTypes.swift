//
//  ProtocolTypes.swift
//  spacetimedb-swift-sdk
//
//  Shared v2 wire-protocol value types
//  (crates/client-api-messages/src/websocket/{common,v2}.rs).
//

import Foundation
import BSATN

/// Opaque client-supplied identifier for a query set subscription.
/// Wire format: a 1-field product, so the encoding is just `id` (u32).
public struct QuerySetId: Hashable, Sendable {
    public let id: UInt32
    public init(_ id: UInt32) { self.id = id }
    init(reader: BSATNReader) throws { self.id = try reader.read() }
    func encode(to writer: BSATNWriter) { writer.write(id) }
}

/// Flags carried in a v2 `Unsubscribe` message.
/// Default = drop the rows silently. SendDroppedRows = include the
/// dropped rows in the corresponding `UnsubscribeApplied`.
public enum UnsubscribeFlags: UInt8, Sendable {
    case `default` = 0
    case sendDroppedRows = 1

    init(reader: BSATNReader) throws {
        let raw: UInt8 = try reader.read()
        guard let flag = UnsubscribeFlags(rawValue: raw) else {
            throw BSATNError.unsupportedTag(raw)
        }
        self = flag
    }
    func encode(to writer: BSATNWriter) { writer.write(rawValue) }
}

/// Reserved flags for `CallReducer`. Currently a single `default = 0` variant.
public enum CallReducerFlags: UInt8, Sendable {
    case `default` = 0

    init(reader: BSATNReader) throws {
        let raw: UInt8 = try reader.read()
        guard let flag = CallReducerFlags(rawValue: raw) else {
            throw BSATNError.unsupportedTag(raw)
        }
        self = flag
    }
    func encode(to writer: BSATNWriter) { writer.write(rawValue) }
}

/// Reserved flags for `CallProcedure`. Currently a single `default = 0` variant.
public enum CallProcedureFlags: UInt8, Sendable {
    case `default` = 0

    init(reader: BSATNReader) throws {
        let raw: UInt8 = try reader.read()
        guard let flag = CallProcedureFlags(rawValue: raw) else {
            throw BSATNError.unsupportedTag(raw)
        }
        self = flag
    }
    func encode(to writer: BSATNWriter) { writer.write(rawValue) }
}
