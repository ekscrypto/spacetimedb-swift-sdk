import Testing
import Foundation
@testable import SpacetimeDB

@Suite("ClientMetrics")
struct ClientMetricsTests {

    @Test func snapshotIsNilBeforeAnyRecord() async {
        let m = ClientMetrics(bucketUpperBounds: [16, 64, 256])
        let snap = await m.snapshot(db: "anything")
        #expect(snap == nil)
    }

    @Test func recordIncrementsCountAndBytes() async {
        let m = ClientMetrics(bucketUpperBounds: [16, 64, 256])
        await m.recordReceived(db: "x", byteCount: 10)
        await m.recordReceived(db: "x", byteCount: 50)
        let snap = await m.snapshot(db: "x")!
        #expect(snap.messagesReceived == 2)
        #expect(snap.bytesReceived == 60)
    }

    @Test func bucketsAreNotCumulative() async {
        // Frames 10 and 12 both fall in bucket 0 (le 16);
        // 50 falls in bucket 1 (le 64); 100 falls in bucket 2 (le 256).
        let m = ClientMetrics(bucketUpperBounds: [16, 64, 256])
        await m.recordReceived(db: "x", byteCount: 10)
        await m.recordReceived(db: "x", byteCount: 12)
        await m.recordReceived(db: "x", byteCount: 50)
        await m.recordReceived(db: "x", byteCount: 100)
        let snap = await m.snapshot(db: "x")!
        #expect(snap.bucketCounts == [2, 1, 1])
        #expect(snap.bucketOverflowCount == 0)
    }

    @Test func boundaryFallsIntoTheBucketItEquals() async {
        // Boundary check: a frame whose size equals the upper bound
        // should land in that bucket (le semantics).
        let m = ClientMetrics(bucketUpperBounds: [16, 64])
        await m.recordReceived(db: "x", byteCount: 16)
        await m.recordReceived(db: "x", byteCount: 64)
        let snap = await m.snapshot(db: "x")!
        #expect(snap.bucketCounts == [1, 1])
    }

    @Test func framesAboveLargestBucketLandInOverflow() async {
        let m = ClientMetrics(bucketUpperBounds: [16, 64])
        await m.recordReceived(db: "x", byteCount: 65)
        await m.recordReceived(db: "x", byteCount: 1_000_000)
        let snap = await m.snapshot(db: "x")!
        #expect(snap.bucketCounts == [0, 0])
        #expect(snap.bucketOverflowCount == 2)
    }

    @Test func perDBIsolation() async {
        let m = ClientMetrics(bucketUpperBounds: [64])
        await m.recordReceived(db: "alpha", byteCount: 10)
        await m.recordReceived(db: "alpha", byteCount: 20)
        await m.recordReceived(db: "beta", byteCount: 30)

        let alpha = await m.snapshot(db: "alpha")!
        let beta = await m.snapshot(db: "beta")!
        #expect(alpha.messagesReceived == 2)
        #expect(alpha.bytesReceived == 30)
        #expect(beta.messagesReceived == 1)
        #expect(beta.bytesReceived == 30)

        let all = await m.snapshotAll()
        #expect(Set(all.keys) == ["alpha", "beta"])
    }

    @Test func resetClearsAllDBs() async {
        let m = ClientMetrics(bucketUpperBounds: [64])
        await m.recordReceived(db: "alpha", byteCount: 10)
        await m.recordReceived(db: "beta", byteCount: 10)
        await m.reset()
        #expect(await m.snapshot(db: "alpha") == nil)
        #expect(await m.snapshot(db: "beta") == nil)
        #expect(await m.snapshotAll().isEmpty)
    }

    @Test func defaultBucketsAreSortedAscending() {
        let b = ClientMetrics.defaultBucketUpperBounds
        #expect(b == b.sorted())
        #expect(b.first! < b.last!)
    }
}
