//
//  TimeDuration.swift
//  spacetimedb-swift-sdk
//

import Foundation

/// SpacetimeDB TimeDuration — a signed 64-bit count of microseconds.
/// Mirrors `spacetimedb_lib::TimeDuration` in the reference Rust SDK.
///
/// Wire encoding is a bare `i64`.
public struct TimeDuration: Sendable, Equatable, Hashable, Comparable, Codable {
    public let micros: Int64

    public init(micros: Int64) {
        self.micros = micros
    }

    public init(milliseconds: Int64) {
        self.micros = milliseconds &* 1_000
    }

    public init(seconds: Double) {
        self.micros = Int64((seconds * 1_000_000).rounded())
    }

    public init(timeInterval: TimeInterval) {
        self.init(seconds: timeInterval)
    }

    public static let zero = TimeDuration(micros: 0)

    public var seconds: Double { Double(micros) / 1_000_000 }
    public var timeInterval: TimeInterval { seconds }

    public static func + (lhs: TimeDuration, rhs: TimeDuration) -> TimeDuration {
        TimeDuration(micros: lhs.micros + rhs.micros)
    }

    public static func - (lhs: TimeDuration, rhs: TimeDuration) -> TimeDuration {
        TimeDuration(micros: lhs.micros - rhs.micros)
    }

    public static prefix func - (x: TimeDuration) -> TimeDuration {
        TimeDuration(micros: -x.micros)
    }

    public static func * (lhs: TimeDuration, rhs: Int64) -> TimeDuration {
        TimeDuration(micros: lhs.micros * rhs)
    }

    public static func * (lhs: Int64, rhs: TimeDuration) -> TimeDuration {
        TimeDuration(micros: lhs * rhs.micros)
    }

    public func checkedAdd(_ other: TimeDuration) -> TimeDuration? {
        let (sum, overflow) = micros.addingReportingOverflow(other.micros)
        return overflow ? nil : TimeDuration(micros: sum)
    }

    public func checkedSub(_ other: TimeDuration) -> TimeDuration? {
        let (diff, overflow) = micros.subtractingReportingOverflow(other.micros)
        return overflow ? nil : TimeDuration(micros: diff)
    }

    public static func < (lhs: TimeDuration, rhs: TimeDuration) -> Bool {
        lhs.micros < rhs.micros
    }
}

extension TimeDuration {
    public init(reader: BSATNReader) throws {
        let micros: Int64 = try reader.read()
        self.init(micros: micros)
    }

    public func write(to writer: BSATNWriter) {
        writer.write(micros)
    }
}
