//
//  Timestamp.swift
//  spacetimedb-swift-sdk
//

import Foundation

/// SpacetimeDB Timestamp — a signed-64-bit count of microseconds since the
/// Unix epoch. Mirrors `spacetimedb_lib::Timestamp` in the reference Rust SDK.
///
/// Wire encoding is a bare `i64` (the same bytes a `UInt64` "now" timestamp
/// has occupied in this SDK historically), so reading existing
/// `TransactionUpdate.timestamp` via `Timestamp(reader:)` is byte-compatible.
public struct Timestamp: Sendable, Equatable, Hashable, Comparable, Codable {
    public let microsSinceUnixEpoch: Int64

    public init(microsSinceUnixEpoch: Int64) {
        self.microsSinceUnixEpoch = microsSinceUnixEpoch
    }

    public init(date: Date) {
        // Round-half-away-from-zero so symmetric pre/post-epoch dates are stable.
        let micros = (date.timeIntervalSince1970 * 1_000_000).rounded()
        self.microsSinceUnixEpoch = Int64(micros)
    }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(microsSinceUnixEpoch) / 1_000_000)
    }

    public static let epoch = Timestamp(microsSinceUnixEpoch: 0)

    public static func < (lhs: Timestamp, rhs: Timestamp) -> Bool {
        lhs.microsSinceUnixEpoch < rhs.microsSinceUnixEpoch
    }
}

extension Timestamp {
    public init(reader: BSATNReader) throws {
        let micros: Int64 = try reader.read()
        self.init(microsSinceUnixEpoch: micros)
    }

    public func write(to writer: BSATNWriter) {
        writer.write(microsSinceUnixEpoch)
    }
}
