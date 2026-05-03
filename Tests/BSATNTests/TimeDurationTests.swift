import Testing
import Foundation
@testable import BSATN

@Suite("TimeDuration Tests")
struct TimeDurationTests {

    @Test func zeroIsZero() {
        #expect(TimeDuration.zero.micros == 0)
    }

    @Test func secondsConversion() {
        let d = TimeDuration(seconds: 1.5)
        #expect(d.micros == 1_500_000)
        #expect(d.seconds == 1.5)
        #expect(d.timeInterval == 1.5)
    }

    @Test func millisecondsConversion() {
        let d = TimeDuration(milliseconds: 250)
        #expect(d.micros == 250_000)
    }

    @Test func arithmetic() {
        let a = TimeDuration(micros: 1_000)
        let b = TimeDuration(micros: 500)
        #expect((a + b).micros == 1_500)
        #expect((a - b).micros == 500)
        #expect((-a).micros == -1_000)
        #expect((a * 3).micros == 3_000)
        #expect((3 * a).micros == 3_000)
    }

    @Test func comparable() {
        let small = TimeDuration(micros: 10)
        let large = TimeDuration(micros: 100)
        #expect(small < large)
        #expect(!(large < small))
        #expect(small != large)
    }

    @Test func checkedOverflow() {
        let near = TimeDuration(micros: Int64.max - 5)
        let big = TimeDuration(micros: 10)
        #expect(near.checkedAdd(big) == nil)
        #expect(near.checkedAdd(TimeDuration(micros: 5)) != nil)

        let lower = TimeDuration(micros: Int64.min + 5)
        #expect(lower.checkedSub(big) == nil)
    }

    @Test func bsatnRoundTrip() throws {
        let original = TimeDuration(micros: -1_234_567_890)
        let writer = BSATNWriter()
        original.write(to: writer)
        let reader = BSATNReader(data: writer.finalize())
        let decoded = try TimeDuration(reader: reader)
        #expect(decoded == original)
    }

    @Test func bsatnIs8Bytes() throws {
        let d = TimeDuration(micros: 1)
        let writer = BSATNWriter()
        d.write(to: writer)
        let bytes = writer.finalize()
        #expect(bytes.count == 8)
        #expect(Array(bytes) == [0x01, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test func extremeValues() throws {
        for v in [Int64.min, Int64.max] {
            let d = TimeDuration(micros: v)
            let writer = BSATNWriter()
            d.write(to: writer)
            let reader = BSATNReader(data: writer.finalize())
            let decoded = try TimeDuration(reader: reader)
            #expect(decoded.micros == v)
        }
    }

    @Test func jsonRoundTrip() throws {
        let original = TimeDuration(micros: 42_000_000)
        let json = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimeDuration.self, from: json)
        #expect(decoded == original)
    }
}
