//
//  ConnectionId.swift
//  spacetimedb-swift-sdk
//

import Foundation

/// SpacetimeDB ConnectionId — a 16-byte identifier the server assigns per
/// WebSocket session. Mirrors `spacetimedb_lib::ConnectionId` in the Rust SDK
/// and the `Identity`-shaped 16-byte UUID-like type used elsewhere.
///
/// Wire encoding is a bare `u128` (16 bytes), matching the existing
/// `BSATN.UInt128` reader/writer paths.
public struct ConnectionId: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    public let raw: UInt128

    public init(_ raw: UInt128) {
        self.raw = raw
    }

    public init?(hexString: String) {
        guard hexString.count == 32 else { return nil }
        let halfIndex = hexString.index(hexString.startIndex, offsetBy: 16)
        let u1Hex = String(hexString[hexString.startIndex..<halfIndex])
        let u0Hex = String(hexString[halfIndex...])
        guard let u0 = UInt64(u0Hex, radix: 16),
              let u1 = UInt64(u1Hex, radix: 16) else { return nil }
        self.raw = UInt128(u0: u0, u1: u1)
    }

    /// Full 32-character lowercase hex string.
    public var hexString: String {
        raw.description
    }

    /// First 8 hex characters — handy for human-readable logs.
    public var abbreviated: String {
        String(hexString.prefix(8))
    }

    public var description: String { hexString }
}

extension ConnectionId {
    public init(reader: BSATNReader) throws {
        let raw: UInt128 = try reader.read()
        self.init(raw)
    }

    public func write(to writer: BSATNWriter) {
        writer.write(raw)
    }
}
