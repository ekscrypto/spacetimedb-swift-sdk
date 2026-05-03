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

extension Timestamp {
    /// Wall-clock now as a `Timestamp`.
    public static var now: Timestamp { Timestamp(date: Date()) }

    public static func + (lhs: Timestamp, rhs: TimeDuration) -> Timestamp {
        Timestamp(microsSinceUnixEpoch: lhs.microsSinceUnixEpoch + rhs.micros)
    }

    public static func - (lhs: Timestamp, rhs: TimeDuration) -> Timestamp {
        Timestamp(microsSinceUnixEpoch: lhs.microsSinceUnixEpoch - rhs.micros)
    }

    public static func - (lhs: Timestamp, rhs: Timestamp) -> TimeDuration {
        TimeDuration(micros: lhs.microsSinceUnixEpoch - rhs.microsSinceUnixEpoch)
    }

    /// Signed duration from `other` to `self`.
    public func durationSince(_ other: Timestamp) -> TimeDuration {
        self - other
    }

    public func checkedAdd(_ duration: TimeDuration) -> Timestamp? {
        let (sum, overflow) = microsSinceUnixEpoch.addingReportingOverflow(duration.micros)
        return overflow ? nil : Timestamp(microsSinceUnixEpoch: sum)
    }

    public func checkedSub(_ duration: TimeDuration) -> Timestamp? {
        let (diff, overflow) = microsSinceUnixEpoch.subtractingReportingOverflow(duration.micros)
        return overflow ? nil : Timestamp(microsSinceUnixEpoch: diff)
    }
}

extension Timestamp {
    /// RFC 3339 / ISO 8601 string with fractional-second precision suitable for
    /// round-tripping microsecond timestamps. Always emits UTC ("Z").
    public var rfc3339: String {
        Self.makeFormatter(withFractionalSeconds: true).string(from: date)
    }

    /// Parse an RFC 3339 / ISO 8601 timestamp. Accepts strings with or without
    /// fractional seconds.
    public init?(rfc3339: String) {
        if let d = Self.makeFormatter(withFractionalSeconds: true).date(from: rfc3339) {
            self.init(date: d)
            return
        }
        if let d = Self.makeFormatter(withFractionalSeconds: false).date(from: rfc3339) {
            self.init(date: d)
            return
        }
        return nil
    }

    /// Construct a fresh `ISO8601DateFormatter` per call. Apple's docs claim
    /// `ISO8601DateFormatter` is thread-safe, but on macOS 26.x the underlying
    /// ICU `SimpleDateFormat` shows mutex contention that has corrupted
    /// concurrently-running test threads in practice. Allocating per call is
    /// microseconds-cheap and avoids the shared-state hazard entirely.
    private static func makeFormatter(withFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = withFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return f
    }
}
