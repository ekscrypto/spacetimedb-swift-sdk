//
//  Uuid.swift
//  spacetimedb-swift-sdk
//
//  Phase 15: SpacetimeDB Uuid value type. Mirrors the TS v3 SDK's
//  `Uuid` sum: `Nil` / `V4` / `V7` / `Max` variants, all backed by
//  a single u128 payload on the wire.
//
//  Wire format (BSATN sum):
//      tag: u8  (0 = Nil, 1 = V4, 2 = V7, 3 = Max)
//      payload: u128
//
//  The variant byte preserves UUID version semantics so both server
//  and client can reason about freshness without a second round trip.
//

import Foundation

public enum Uuid: Sendable, Equatable, Hashable, Codable {
    case nil_(UInt128)
    case v4(UInt128)
    case v7(UInt128)
    case max(UInt128)

    /// Underlying 128-bit value, regardless of variant.
    public var rawValue: UInt128 {
        switch self {
        case .nil_(let v), .v4(let v), .v7(let v), .max(let v): return v
        }
    }

    /// Wire-tag byte (0 / 1 / 2 / 3).
    public var tag: UInt8 {
        switch self {
        case .nil_: return 0
        case .v4:   return 1
        case .v7:   return 2
        case .max:  return 3
        }
    }

    /// All-zero Uuid (RFC 4122 nil UUID, often used as a sentinel).
    public static let zero: Uuid = .nil_(UInt128(u0: 0, u1: 0))

    /// All-ones Uuid (RFC 4122 max UUID, sentinel for upper bounds).
    public static let allOnes: Uuid = .max(UInt128(u0: .max, u1: .max))
}

extension Uuid {
    public init(reader: BSATNReader) throws {
        let tag: UInt8 = try reader.read()
        let value: UInt128 = try reader.read()
        switch tag {
        case 0: self = .nil_(value)
        case 1: self = .v4(value)
        case 2: self = .v7(value)
        case 3: self = .max(value)
        default: throw BSATNError.invalidSumTag(tag)
        }
    }

    public func write(to writer: BSATNWriter) {
        writer.write(tag)
        writer.write(rawValue)
    }
}
