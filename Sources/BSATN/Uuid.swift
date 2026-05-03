//
//  Uuid.swift
//  spacetimedb-swift-sdk
//
//  SpacetimeDB Uuid value type. Mirrors the TS v3 SDK's
//  `Uuid` sum: `Nil` / `V4` / `V7` / `Max` variants, all backed by
//  a single u128 payload on the wire.
//
//  Wire format (BSATN sum):
//      tag: u8  (0 = Nil, 1 = V4, 2 = V7, 3 = Max)
//      payload: u128
//
//  Per RFC 9562:
//    • The Nil UUID (§5.9) and Max UUID (§5.10) are special-case
//      values — explicitly all-zeros and all-ones bytes respectively,
//      with no version or variant fields. `Uuid.zero` / `Uuid.allOnes`
//      below are the canonical instances.
//    • V4 and V7 payloads, however, MUST have specific version and
//      variant bits set: byte 6 high nibble = 0x40 (v4) or 0x70 (v7),
//      and byte 8 high two bits = 0b10 (RFC 4122 variant). The SDK
//      does NOT enforce or compute these — clients are expected to
//      receive well-formed UUIDs from the server (which generates
//      them with the correct bits) and to round-trip them as opaque
//      u128 payloads. If you need to construct a fresh UUID
//      client-side, use Apple's `UUID()` and pass its raw bytes
//      through; the BSATN-vs-canonical byte ordering is intentionally
//      not addressed at this layer until the server's exact wire
//      shape for `Uuid` is documented in the upstream protocol spec.
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

    /// All-zeros Uuid (RFC 9562 §5.9 Nil UUID — explicitly defined
    /// as a valid special-case value with no version/variant field).
    public static let zero: Uuid = .nil_(UInt128(u0: 0, u1: 0))

    /// All-ones Uuid (RFC 9562 §5.10 Max UUID — explicitly defined
    /// as a valid special-case value, often used as an upper-bound
    /// sentinel in range queries).
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
