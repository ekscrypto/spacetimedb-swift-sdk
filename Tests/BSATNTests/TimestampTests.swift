import Testing
import Foundation
@testable import BSATN

@Suite("Timestamp Tests")
struct TimestampTests {

    @Test func epochIsZero() {
        #expect(Timestamp.epoch.microsSinceUnixEpoch == 0)
        #expect(Timestamp.epoch.date == Date(timeIntervalSince1970: 0))
    }

    @Test func dateRoundTripIsLossless() {
        // Pick a date with whole microseconds so floating-point doesn't bite.
        let original = Date(timeIntervalSince1970: 1_700_000_000.123_456)
        let timestamp = Timestamp(date: original)
        #expect(timestamp.microsSinceUnixEpoch == 1_700_000_000_123_456)
        #expect(abs(timestamp.date.timeIntervalSince1970 - original.timeIntervalSince1970) < 1e-6)
    }

    @Test func microsConstructorRoundTrip() {
        let micros: Int64 = 1_234_567_890_123_456
        let timestamp = Timestamp(microsSinceUnixEpoch: micros)
        #expect(timestamp.microsSinceUnixEpoch == micros)
    }

    @Test func bsatnRoundTrip() throws {
        let original = Timestamp(microsSinceUnixEpoch: 1_700_000_000_000_000)
        let writer = BSATNWriter()
        original.write(to: writer)

        let reader = BSATNReader(data: writer.finalize())
        let decoded = try Timestamp(reader: reader)

        #expect(decoded == original)
    }

    @Test func bsatnEncodesAsBareI64() throws {
        // Verify wire format: 8 bytes little-endian Int64.
        let timestamp = Timestamp(microsSinceUnixEpoch: 1)
        let writer = BSATNWriter()
        timestamp.write(to: writer)
        let bytes = writer.finalize()
        #expect(bytes.count == 8)
        #expect(Array(bytes) == [0x01, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test func negativeTimestampIsSupported() throws {
        // Pre-epoch timestamp.
        let original = Timestamp(microsSinceUnixEpoch: -1_000_000)
        let writer = BSATNWriter()
        original.write(to: writer)

        let reader = BSATNReader(data: writer.finalize())
        let decoded = try Timestamp(reader: reader)

        #expect(decoded.microsSinceUnixEpoch == -1_000_000)
        #expect(decoded.date.timeIntervalSince1970 == -1.0)
    }

    @Test func extremeValues() throws {
        for value in [Int64.min, Int64.max] {
            let original = Timestamp(microsSinceUnixEpoch: value)
            let writer = BSATNWriter()
            original.write(to: writer)
            let reader = BSATNReader(data: writer.finalize())
            let decoded = try Timestamp(reader: reader)
            #expect(decoded.microsSinceUnixEpoch == value)
        }
    }

    @Test func comparable() {
        let earlier = Timestamp(microsSinceUnixEpoch: 100)
        let later = Timestamp(microsSinceUnixEpoch: 200)
        #expect(earlier < later)
        #expect(!(later < earlier))
        #expect(earlier != later)
    }

    @Test func hashableAndEquatable() {
        let a = Timestamp(microsSinceUnixEpoch: 42)
        let b = Timestamp(microsSinceUnixEpoch: 42)
        let c = Timestamp(microsSinceUnixEpoch: 43)
        #expect(a == b)
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }

    @Test func codableRoundTrip() throws {
        let original = Timestamp(microsSinceUnixEpoch: 1_700_000_000_000_000)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Timestamp.self, from: encoded)
        #expect(decoded == original)
    }
}
