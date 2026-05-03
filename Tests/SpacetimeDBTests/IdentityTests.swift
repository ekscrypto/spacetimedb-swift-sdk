import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("Identity Tests")
struct IdentityTests {

    @Test func zeroIsAllZeros() {
        #expect(Identity.zero.value == UInt256(u0: 0, u1: 0, u2: 0, u3: 0))
        #expect(Identity.zero.hex == String(repeating: "0", count: 64))
    }

    @Test func hexRoundTrip() throws {
        let hex = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        let id = try #require(Identity(hex: hex))
        #expect(id.hex == hex)
        #expect(id.description == hex)
    }

    @Test func hexRejectsWrongLength() {
        #expect(Identity(hex: "abc") == nil)
        #expect(Identity(hex: String(repeating: "a", count: 63)) == nil)
        #expect(Identity(hex: String(repeating: "a", count: 65)) == nil)
    }

    @Test func hexRejectsNonHex() {
        #expect(Identity(hex: String(repeating: "z", count: 64)) == nil)
    }

    @Test func abbreviatedIs16Chars() throws {
        let hex = "deadbeefcafebabe0123456789abcdef0123456789abcdef0123456789abcdef"
        let id = try #require(Identity(hex: hex))
        #expect(id.abbreviated == "deadbeefcafebabe")
        #expect(id.abbreviated.count == 16)
    }

    @Test func bsatnRoundTrip() throws {
        let original = try #require(Identity(hex: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"))
        let writer = BSATNWriter()
        original.write(to: writer)
        let reader = BSATNReader(data: writer.finalize())
        let decoded = try Identity(reader: reader)
        #expect(decoded == original)
    }

    @Test func bsatnIs32Bytes() throws {
        let id = Identity.zero
        let writer = BSATNWriter()
        id.write(to: writer)
        #expect(writer.finalize().count == 32)
    }

    @Test func jsonRoundTripIsHexString() throws {
        let original = try #require(Identity(hex: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"))
        let json = try JSONEncoder().encode(original)
        // Single-value container — must encode as a JSON string.
        let asString = try #require(String(data: json, encoding: .utf8))
        #expect(asString == "\"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\"")
        let decoded = try JSONDecoder().decode(Identity.self, from: json)
        #expect(decoded == original)
    }

    @Test func jsonRejectsBadHex() {
        let bad = #"""
        "abc"
        """#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Identity.self, from: bad)
        }
    }

    @Test func equatableHashable() throws {
        let a = try #require(Identity(hex: String(repeating: "a", count: 64)))
        let b = try #require(Identity(hex: String(repeating: "a", count: 64)))
        let c = try #require(Identity(hex: String(repeating: "b", count: 64)))
        #expect(a == b)
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }

    @Test func wrappingUInt256Preserves() {
        let raw = UInt256(u0: 1, u1: 2, u2: 3, u3: 4)
        let id = Identity(raw)
        #expect(id.value == raw)
    }
}
