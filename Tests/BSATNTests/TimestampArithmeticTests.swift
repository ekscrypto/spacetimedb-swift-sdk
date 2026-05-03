import Testing
import Foundation
@testable import BSATN

@Suite("Timestamp arithmetic + RFC3339 Tests")
struct TimestampArithmeticTests {

    @Test func nowIsRecent() {
        let before = Date().timeIntervalSince1970
        let now = Timestamp.now
        let after = Date().timeIntervalSince1970
        let nowSeconds = Double(now.microsSinceUnixEpoch) / 1_000_000
        #expect(nowSeconds >= before - 0.001)
        #expect(nowSeconds <= after + 0.001)
    }

    @Test func addDurationShifts() {
        let base = Timestamp(microsSinceUnixEpoch: 1_000_000_000)
        let shifted = base + TimeDuration(micros: 500)
        #expect(shifted.microsSinceUnixEpoch == 1_000_000_500)
    }

    @Test func subDurationShifts() {
        let base = Timestamp(microsSinceUnixEpoch: 1_000_000_000)
        let shifted = base - TimeDuration(micros: 500)
        #expect(shifted.microsSinceUnixEpoch == 999_999_500)
    }

    @Test func subTimestampYieldsDuration() {
        let later = Timestamp(microsSinceUnixEpoch: 2_000_000_000)
        let earlier = Timestamp(microsSinceUnixEpoch: 1_000_000_000)
        let delta: TimeDuration = later - earlier
        #expect(delta.micros == 1_000_000_000)
        #expect(later.durationSince(earlier) == delta)
    }

    @Test func checkedAddOverflows() {
        let near = Timestamp(microsSinceUnixEpoch: Int64.max - 5)
        #expect(near.checkedAdd(TimeDuration(micros: 10)) == nil)
        #expect(near.checkedAdd(TimeDuration(micros: 5)) != nil)
    }

    @Test func checkedSubOverflows() {
        let near = Timestamp(microsSinceUnixEpoch: Int64.min + 5)
        #expect(near.checkedSub(TimeDuration(micros: 10)) == nil)
    }

    @Test func rfc3339RoundTripWithFractional() throws {
        // 2023-11-14T22:13:20.123456 UTC = 1_700_000_000_123_456 micros since epoch
        let original = Timestamp(microsSinceUnixEpoch: 1_700_000_000_123_000)
        let str = original.rfc3339
        let parsed = try #require(Timestamp(rfc3339: str))
        // Allow up to 1 microsecond rounding (ISO formatter is millisecond-precision).
        #expect(abs(parsed.microsSinceUnixEpoch - original.microsSinceUnixEpoch) <= 1_000)
    }

    @Test func rfc3339ParsesNoFractional() throws {
        let parsed = try #require(Timestamp(rfc3339: "2023-11-14T22:13:20Z"))
        #expect(parsed.microsSinceUnixEpoch == 1_700_000_000_000_000)
    }

    @Test func rfc3339RejectsGarbage() {
        #expect(Timestamp(rfc3339: "not a date") == nil)
        #expect(Timestamp(rfc3339: "") == nil)
    }
}
