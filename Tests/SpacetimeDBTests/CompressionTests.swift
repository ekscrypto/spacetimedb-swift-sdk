import Testing
@testable import SpacetimeDB
@testable import BSATN

@Suite("Compression Tests")
struct CompressionTests {

    @Test("Compression enum raw values match SpacetimeDB protocol bytes")
    func compressionEnumValues() {
        // Per the SpacetimeDB wire protocol:
        //   SERVER_MSG_COMPRESSION_TAG_NONE   = 0
        //   SERVER_MSG_COMPRESSION_TAG_BROTLI = 1
        //   SERVER_MSG_COMPRESSION_TAG_GZIP   = 2
        #expect(Compression.none.rawValue == 0)
        #expect(Compression.brotli.rawValue == 1)
        #expect(Compression.gzip.rawValue == 2)
    }

    @Test("Compression from raw value")
    func compressionFromRawValue() {
        #expect(Compression(rawValue: 0) == Compression.none)
        #expect(Compression(rawValue: 1) == Compression.brotli)
        #expect(Compression(rawValue: 2) == Compression.gzip)
        #expect(Compression(rawValue: 3) == nil)
    }

    @Test("Compression CaseIterable conformance")
    func compressionCaseIterable() {
        let allCases = Compression.allCases
        #expect(allCases.count == 3)
        #expect(allCases.contains(.none))
        #expect(allCases.contains(.gzip))
        #expect(allCases.contains(.brotli))
    }

    @Test("Compression equality")
    func compressionEquality() {
        #expect(Compression.none == Compression.none)
        #expect(Compression.none != Compression.gzip)
        #expect(Compression.gzip != Compression.brotli)
    }

    @Test("Compression server string representation")
    func compressionServerString() {
        #expect(Compression.none.serverString == "None")
        #expect(Compression.gzip.serverString == "Gzip")
        #expect(Compression.brotli.serverString == "Brotli")
    }
}