import Testing
import Foundation
@testable import BSATN

@Suite("ScheduleAt Tests")
struct ScheduleAtTests {

    @Test func intervalRoundTrip() throws {
        let original = ScheduleAt.interval(TimeDuration(micros: 1_000_000))
        let writer = BSATNWriter()
        original.write(to: writer)
        let reader = BSATNReader(data: writer.finalize())
        let decoded = try ScheduleAt(reader: reader)
        #expect(decoded == original)
    }

    @Test func timeRoundTrip() throws {
        let original = ScheduleAt.time(Timestamp(microsSinceUnixEpoch: 1_700_000_000_000_000))
        let writer = BSATNWriter()
        original.write(to: writer)
        let reader = BSATNReader(data: writer.finalize())
        let decoded = try ScheduleAt(reader: reader)
        #expect(decoded == original)
    }

    @Test func intervalTagIsZero() throws {
        let writer = BSATNWriter()
        ScheduleAt.interval(TimeDuration(micros: 1)).write(to: writer)
        let bytes = writer.finalize()
        #expect(bytes.count == 9)        // 1 tag + 8 i64
        #expect(bytes.first == 0x00)
    }

    @Test func timeTagIsOne() throws {
        let writer = BSATNWriter()
        ScheduleAt.time(Timestamp(microsSinceUnixEpoch: 1)).write(to: writer)
        let bytes = writer.finalize()
        #expect(bytes.count == 9)
        #expect(bytes.first == 0x01)
    }

    @Test func invalidTagThrows() {
        let bad = Data([0x02, 0, 0, 0, 0, 0, 0, 0, 0])
        let reader = BSATNReader(data: bad)
        #expect(throws: BSATNError.self) {
            _ = try ScheduleAt(reader: reader)
        }
    }

    @Test func jsonRoundTrip() throws {
        let original = ScheduleAt.interval(TimeDuration(micros: 5_000_000))
        let json = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScheduleAt.self, from: json)
        #expect(decoded == original)
    }
}
