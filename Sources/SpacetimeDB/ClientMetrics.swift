//
//  ClientMetrics.swift
//  spacetimedb-swift-sdk
//
//  Process-global metrics about WebSocket traffic, mirroring the Rust
//  SDK's `unstable::CLIENT_METRICS` (sdks/rust/src/metrics.rs).
//
//  Rust exposes:
//    - websocket_received           : IntCounterVec   labelled by db
//    - websocket_received_msg_size  : HistogramVec    labelled by db
//
//  We expose the same two signals as a per-db `DBMetrics` snapshot.
//  Buckets are byte-oriented (Prometheus's default time buckets aren't
//  meaningful for message size). Snapshots are point-in-time; the actor
//  itself is the source of truth.
//

import Foundation

/// Per-database WebSocket metrics snapshot. Cumulative counters; the
/// histogram buckets are inclusive upper bounds in bytes.
public struct DBMetrics: Sendable, Equatable {
    /// Total inbound WebSocket frames seen for this db (pre-decompression).
    public let messagesReceived: UInt64
    /// Total bytes across `messagesReceived` (sum of every frame's size).
    public let bytesReceived: UInt64
    /// Per-bucket counts. `bucketUpperBounds[i]` is the inclusive upper
    /// bound (in bytes) for `bucketCounts[i]`. Mirrors Prometheus
    /// `histogram_bucket{le="..."}` semantics — counts are NOT
    /// cumulative across buckets (they're per-bucket).
    public let bucketUpperBounds: [UInt64]
    public let bucketCounts: [UInt64]
    /// Frames whose size exceeded the largest bucket.
    public let bucketOverflowCount: UInt64

    public init(
        messagesReceived: UInt64,
        bytesReceived: UInt64,
        bucketUpperBounds: [UInt64],
        bucketCounts: [UInt64],
        bucketOverflowCount: UInt64
    ) {
        self.messagesReceived = messagesReceived
        self.bytesReceived = bytesReceived
        self.bucketUpperBounds = bucketUpperBounds
        self.bucketCounts = bucketCounts
        self.bucketOverflowCount = bucketOverflowCount
    }
}

/// Process-global, actor-isolated counter store. Use the `shared`
/// singleton to read snapshots; the SDK writes to it from the receive
/// loop. There is no public mutation API beyond `reset()` so tests can
/// isolate themselves.
public actor ClientMetrics {

    /// Singleton matching Rust's `unstable::CLIENT_METRICS`.
    public static let shared = ClientMetrics()

    /// Inclusive upper bounds for the size histogram, in bytes. Picked
    /// to span typical SpacetimeDB frames (small reducer responses up
    /// through multi-MB initial subscriptions). Frames above the
    /// largest bound land in the overflow bucket.
    public static let defaultBucketUpperBounds: [UInt64] = [
        64, 256, 1_024, 4_096, 16_384, 65_536, 262_144, 1_048_576, 4_194_304
    ]

    private struct PerDB {
        var messagesReceived: UInt64 = 0
        var bytesReceived: UInt64 = 0
        var bucketCounts: [UInt64]
        var bucketOverflowCount: UInt64 = 0

        init(bucketCount: Int) {
            self.bucketCounts = Array(repeating: 0, count: bucketCount)
        }
    }

    private let bucketUpperBounds: [UInt64]
    private var perDB: [String: PerDB] = [:]

    /// Tests / advanced users can construct a private metrics instance
    /// with custom buckets if they need to. Production code should use
    /// `ClientMetrics.shared`.
    public init(bucketUpperBounds: [UInt64] = ClientMetrics.defaultBucketUpperBounds) {
        precondition(bucketUpperBounds == bucketUpperBounds.sorted(), "bucketUpperBounds must be ascending")
        self.bucketUpperBounds = bucketUpperBounds
    }

    /// Record an inbound WebSocket frame. The SDK calls this from its
    /// receive loop with the raw frame size (pre-decompression) and the
    /// db name from the connection that received it.
    public func recordReceived(db: String, byteCount: Int) {
        var entry = perDB[db] ?? PerDB(bucketCount: bucketUpperBounds.count)
        entry.messagesReceived &+= 1
        entry.bytesReceived &+= UInt64(byteCount)
        let size = UInt64(byteCount)
        if let i = bucketUpperBounds.firstIndex(where: { size <= $0 }) {
            entry.bucketCounts[i] &+= 1
        } else {
            entry.bucketOverflowCount &+= 1
        }
        perDB[db] = entry
    }

    /// Snapshot the current counters for one db, or `nil` if nothing has
    /// been recorded for it yet.
    public func snapshot(db: String) -> DBMetrics? {
        guard let e = perDB[db] else { return nil }
        return DBMetrics(
            messagesReceived: e.messagesReceived,
            bytesReceived: e.bytesReceived,
            bucketUpperBounds: bucketUpperBounds,
            bucketCounts: e.bucketCounts,
            bucketOverflowCount: e.bucketOverflowCount
        )
    }

    /// All known db labels and their snapshots in one pass.
    public func snapshotAll() -> [String: DBMetrics] {
        var out: [String: DBMetrics] = [:]
        for (db, e) in perDB {
            out[db] = DBMetrics(
                messagesReceived: e.messagesReceived,
                bytesReceived: e.bytesReceived,
                bucketUpperBounds: bucketUpperBounds,
                bucketCounts: e.bucketCounts,
                bucketOverflowCount: e.bucketOverflowCount
            )
        }
        return out
    }

    /// Drop all recorded counters. Intended for tests.
    public func reset() {
        perDB.removeAll(keepingCapacity: true)
    }
}
