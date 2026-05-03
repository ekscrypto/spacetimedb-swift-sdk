import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("OneOffQuery Request Tests (v2)")
struct OneOffQueryRequestTests {

    @Test func encodesOneOffQueryRequestCorrectly() throws {
        // v2 wire: tag (0x02) + request_id (u32) + query_string (string).
        // v1 carried a 16-byte messageId blob; v2 collapses to a request_id.
        let request = OneOffQueryRequest(
            requestId: 42,
            queryString: "SELECT * FROM user WHERE id = 42"
        )
        let encoded = try request.encode()
        let reader = BSATNReader(data: encoded)

        let messageTag: UInt8 = try reader.read()
        #expect(messageTag == Tags.ClientMessage.oneOffQuery.rawValue,
                "Message tag should be OneOffQuery (0x02)")

        let requestId: UInt32 = try reader.read()
        #expect(requestId == 42)

        let queryLength: UInt32 = try reader.read()
        #expect(queryLength == UInt32("SELECT * FROM user WHERE id = 42".utf8.count))

        var queryBytes: [UInt8] = []
        for _ in 0..<queryLength { queryBytes.append(try reader.read()) }
        #expect(String(bytes: queryBytes, encoding: .utf8) == "SELECT * FROM user WHERE id = 42")
    }

    @Test func encodesWithUnicodeQuery() throws {
        let unicodeQuery = "SELECT * FROM café WHERE name = '测试用户'"
        let request = OneOffQueryRequest(requestId: 1, queryString: unicodeQuery)
        let encoded = try request.encode()
        let reader = BSATNReader(data: encoded)

        let _: UInt8 = try reader.read()   // tag
        let _: UInt32 = try reader.read()  // requestId

        let queryLength: UInt32 = try reader.read()
        var queryBytes: [UInt8] = []
        for _ in 0..<queryLength { queryBytes.append(try reader.read()) }
        #expect(String(bytes: queryBytes, encoding: .utf8) == unicodeQuery)
    }

    @Test func encodesComplexQuery() throws {
        let complexQuery = """
        SELECT u.name, m.content, m.sent
        FROM user u
        JOIN message m ON u.id = m.sender_id
        WHERE u.created > '2024-01-01'
        ORDER BY m.sent DESC
        LIMIT 100
        """
        let request = OneOffQueryRequest(requestId: 7, queryString: complexQuery)
        let encoded = try request.encode()
        let reader = BSATNReader(data: encoded)

        let messageTag: UInt8 = try reader.read()
        #expect(messageTag == Tags.ClientMessage.oneOffQuery.rawValue)
        let requestId: UInt32 = try reader.read()
        #expect(requestId == 7)
        let queryLength: UInt32 = try reader.read()
        var queryBytes: [UInt8] = []
        for _ in 0..<queryLength { queryBytes.append(try reader.read()) }
        #expect(String(bytes: queryBytes, encoding: .utf8) == complexQuery)
    }

    @Test func producesConsistentEncoding() throws {
        let r1 = OneOffQueryRequest(requestId: 12345, queryString: "SELECT COUNT(*) FROM messages")
        let r2 = OneOffQueryRequest(requestId: 12345, queryString: "SELECT COUNT(*) FROM messages")
        #expect(try r1.encode() == r2.encode(), "Same inputs should produce identical encodings")
    }

    @Test func verifyBinaryStructure() throws {
        let request = OneOffQueryRequest(requestId: 0x12345678, queryString: "test")
        let encoded = try request.encode()

        // tag(0x02) + reqId(4 le) + query_len(4 le) + "test"(4) = 13 bytes
        let expected: [UInt8] = [
            0x02,                       // OneOffQuery tag
            0x78, 0x56, 0x34, 0x12,     // requestId 0x12345678 little-endian
            0x04, 0x00, 0x00, 0x00,     // query length = 4
            0x74, 0x65, 0x73, 0x74      // "test"
        ]
        #expect(Array(encoded) == expected)
    }
}
