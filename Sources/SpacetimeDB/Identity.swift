//
//  Identity.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation
import BSATN

/// SpacetimeDB Identity — a 32-byte (UInt256) opaque identifier the server
/// assigns to a logical user. Distinct from `ConnectionId`, which is per
/// WebSocket session.
///
/// Wire encoding is a bare `UInt256` (32 bytes little-endian limbs). JSON
/// encoding is a 64-character lowercase hex string, matching the
/// `/v1/identity` REST response and the Rust SDK's `Identity::to_hex`.
public struct Identity: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    public let value: UInt256

    public init(_ value: UInt256) {
        self.value = value
    }

    public init?(hex: String) {
        guard hex.count == 64 else { return nil }
        let s = hex.startIndex
        let u3Hex = String(hex[s..<hex.index(s, offsetBy: 16)])
        let u2Hex = String(hex[hex.index(s, offsetBy: 16)..<hex.index(s, offsetBy: 32)])
        let u1Hex = String(hex[hex.index(s, offsetBy: 32)..<hex.index(s, offsetBy: 48)])
        let u0Hex = String(hex[hex.index(s, offsetBy: 48)..<hex.index(s, offsetBy: 64)])
        guard let u0 = UInt64(u0Hex, radix: 16),
              let u1 = UInt64(u1Hex, radix: 16),
              let u2 = UInt64(u2Hex, radix: 16),
              let u3 = UInt64(u3Hex, radix: 16) else { return nil }
        self.value = UInt256(u0: u0, u1: u1, u2: u2, u3: u3)
    }

    public var hex: String { value.description }

    /// First 16 hex characters — handy for human-readable logs.
    public var abbreviated: String { String(hex.prefix(16)) }

    public var description: String { hex }

    public static let zero = Identity(UInt256(u0: 0, u1: 0, u2: 0, u3: 0))

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hexString = try container.decode(String.self)
        guard let id = Identity(hex: hexString) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Identity must be a 64-character lowercase hex string"
            )
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

extension Identity {
    public init(reader: BSATNReader) throws {
        let raw: UInt256 = try reader.read()
        self.init(raw)
    }

    public func write(to writer: BSATNWriter) {
        writer.write(value)
    }
}
