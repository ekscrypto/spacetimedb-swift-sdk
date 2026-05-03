//
//  ScheduleAt.swift
//  spacetimedb-swift-sdk
//

import Foundation

/// SpacetimeDB ScheduleAt — a sum type carried by scheduled-reducer rows.
/// Mirrors `spacetimedb_lib::ScheduleAt`. Tag layout matches the Rust enum
/// declaration order: `0 = .interval`, `1 = .time`.
public enum ScheduleAt: Sendable, Equatable, Hashable, Codable {
    case interval(TimeDuration)
    case time(Timestamp)
}

extension ScheduleAt {
    public init(reader: BSATNReader) throws {
        let tag: UInt8 = try reader.read()
        switch tag {
        case 0:
            let duration = try TimeDuration(reader: reader)
            self = .interval(duration)
        case 1:
            let ts = try Timestamp(reader: reader)
            self = .time(ts)
        default:
            throw BSATNError.invalidSumTag(tag)
        }
    }

    public func write(to writer: BSATNWriter) {
        switch self {
        case .interval(let duration):
            writer.write(UInt8(0))
            duration.write(to: writer)
        case .time(let ts):
            writer.write(UInt8(1))
            ts.write(to: writer)
        }
    }
}
