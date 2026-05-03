import Testing
import Foundation
@testable import BSATN

@Suite("Uuid (Nil/V4/V7/Max) Tests")
struct UuidTests {

    private static let payload = UInt128(u0: 0xDEADBEEF, u1: 0xFEEDFACE)

    @Test func nilTagIsZero() {
        let writer = BSATNWriter()
        Uuid.nil_(UInt128(u0: 0, u1: 0)).write(to: writer)
        let bytes = writer.finalize()
        #expect(bytes.first == 0x00)
        // 1 tag byte + 16 bytes UInt128
        #expect(bytes.count == 17)
    }

    @Test func v4TagIsOne() {
        let writer = BSATNWriter()
        Uuid.v4(Self.payload).write(to: writer)
        let bytes = writer.finalize()
        #expect(bytes.first == 0x01)
    }

    @Test func v7TagIsTwo() {
        let writer = BSATNWriter()
        Uuid.v7(Self.payload).write(to: writer)
        let bytes = writer.finalize()
        #expect(bytes.first == 0x02)
    }

    @Test func maxTagIsThree() {
        let writer = BSATNWriter()
        Uuid.max(Self.payload).write(to: writer)
        let bytes = writer.finalize()
        #expect(bytes.first == 0x03)
    }

    @Test func roundTripPreservesVariantAndPayload() throws {
        for original in [Uuid.nil_(UInt128(u0: 0, u1: 0)), Uuid.v4(Self.payload), Uuid.v7(Self.payload), Uuid.max(Self.payload)] {
            let writer = BSATNWriter()
            original.write(to: writer)
            let reader = BSATNReader(data: writer.finalize())
            let decoded = try Uuid(reader: reader)
            #expect(decoded == original)
        }
    }

    @Test func invalidTagThrows() {
        let bad = Data([0x04] + Data(count: 16))
        let reader = BSATNReader(data: bad)
        #expect(throws: BSATNError.self) {
            _ = try Uuid(reader: reader)
        }
    }

    @Test func zeroAndAllOnesConstants() {
        if case .nil_(let v) = Uuid.zero {
            #expect(v.u0 == 0)
            #expect(v.u1 == 0)
        } else {
            Issue.record("Uuid.zero is not .nil_")
        }
        if case .max(let v) = Uuid.allOnes {
            #expect(v.u0 == .max)
            #expect(v.u1 == .max)
        } else {
            Issue.record("Uuid.allOnes is not .max")
        }
    }

    @Test func rawValueAndTagAccessors() {
        #expect(Uuid.nil_(Self.payload).rawValue == Self.payload)
        #expect(Uuid.v4(Self.payload).rawValue == Self.payload)
        #expect(Uuid.v4(Self.payload).tag == 1)
        #expect(Uuid.v7(Self.payload).tag == 2)
        #expect(Uuid.max(Self.payload).tag == 3)
    }

    @Test func jsonRoundTrip() throws {
        let original = Uuid.v7(Self.payload)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Uuid.self, from: data)
        #expect(decoded == original)
    }
}
