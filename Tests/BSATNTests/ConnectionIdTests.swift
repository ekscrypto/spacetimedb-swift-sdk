import Testing
import Foundation
@testable import BSATN

@Suite("ConnectionId Tests")
struct ConnectionIdTests {

    @Test func initFromUInt128() {
        let raw = UInt128(u0: 0xDEADBEEFCAFEBABE, u1: 0x0123456789ABCDEF)
        let id = ConnectionId(raw)
        #expect(id.raw == raw)
    }

    @Test func hexStringIsFullThirtyTwoChars() {
        let raw = UInt128(u0: 0xDEADBEEFCAFEBABE, u1: 0x0123456789ABCDEF)
        let id = ConnectionId(raw)
        #expect(id.hexString.count == 32)
        // u1 is the high half (printed first), u0 the low half
        #expect(id.hexString == "0123456789abcdefdeadbeefcafebabe")
    }

    @Test func abbreviatedIsFirstEightChars() {
        let raw = UInt128(u0: 0xDEADBEEFCAFEBABE, u1: 0x0123456789ABCDEF)
        let id = ConnectionId(raw)
        #expect(id.abbreviated == "01234567")
        #expect(id.abbreviated.count == 8)
    }

    @Test func hexStringInitRoundTrip() throws {
        let original = ConnectionId(UInt128(u0: 0xCAFEBABEDEADBEEF, u1: 0xFEEDFACECAFEF00D))
        let parsed = try #require(ConnectionId(hexString: original.hexString))
        #expect(parsed == original)
    }

    @Test func hexStringInitRejectsWrongLength() {
        #expect(ConnectionId(hexString: "abc") == nil)
        #expect(ConnectionId(hexString: String(repeating: "f", count: 31)) == nil)
        #expect(ConnectionId(hexString: String(repeating: "f", count: 33)) == nil)
    }

    @Test func hexStringInitRejectsNonHex() {
        #expect(ConnectionId(hexString: String(repeating: "z", count: 32)) == nil)
    }

    @Test func bsatnRoundTrip() throws {
        let original = ConnectionId(UInt128(u0: 0x1122334455667788, u1: 0x99AABBCCDDEEFF00))
        let writer = BSATNWriter()
        original.write(to: writer)

        let reader = BSATNReader(data: writer.finalize())
        let decoded = try ConnectionId(reader: reader)

        #expect(decoded == original)
    }

    @Test func bsatnEncodesAsBareUInt128() {
        // 16 bytes little-endian — same wire as a bare UInt128.
        let id = ConnectionId(UInt128(u0: 1, u1: 0))
        let writer = BSATNWriter()
        id.write(to: writer)
        let bytes = writer.finalize()
        #expect(bytes.count == 16)
        #expect(bytes.first == 0x01)
    }

    @Test func equatableAndHashable() {
        let a = ConnectionId(UInt128(u0: 1, u1: 2))
        let b = ConnectionId(UInt128(u0: 1, u1: 2))
        let c = ConnectionId(UInt128(u0: 1, u1: 3))
        #expect(a == b)
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }

    @Test func codableRoundTrip() throws {
        // Underlying UInt128 is encoded as a hex string; ConnectionId wraps it.
        let original = ConnectionId(UInt128(u0: 0xDEADBEEFCAFEBABE, u1: 0x0123456789ABCDEF))
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectionId.self, from: encoded)
        #expect(decoded == original)
    }

    @Test func descriptionMatchesHexString() {
        let id = ConnectionId(UInt128(u0: 0xCAFEBABE, u1: 0))
        #expect(id.description == id.hexString)
    }
}
