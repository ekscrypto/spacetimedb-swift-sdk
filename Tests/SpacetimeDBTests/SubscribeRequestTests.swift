import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("Subscribe Request Tests (v2)")
struct SubscribeRequestTests {

    @Test func encodesSubscribeRequestCorrectly() throws {
        // v2 wire: tag (0x00) + request_id (u32) + query_set_id (u32) + query_strings ([]string)
        let request = SubscribeRequest(
            requestId: 123_456_789,
            querySetId: QuerySetId(7),
            queryStrings: ["SELECT * FROM user", "SELECT * FROM message"]
        )
        let encoded = try request.encode()
        let reader = BSATNReader(data: encoded)

        let messageTag: UInt8 = try reader.read()
        #expect(messageTag == Tags.ClientMessage.subscribe.rawValue,
                "Message tag should be Subscribe (0x00)")

        let requestId: UInt32 = try reader.read()
        #expect(requestId == 123_456_789)

        let querySetId: UInt32 = try reader.read()
        #expect(querySetId == 7)

        let queryCount: UInt32 = try reader.read()
        #expect(queryCount == 2)

        let q1Len: UInt32 = try reader.read()
        var q1Bytes: [UInt8] = []
        for _ in 0..<q1Len { q1Bytes.append(try reader.read()) }
        #expect(String(bytes: q1Bytes, encoding: .utf8) == "SELECT * FROM user")

        let q2Len: UInt32 = try reader.read()
        var q2Bytes: [UInt8] = []
        for _ in 0..<q2Len { q2Bytes.append(try reader.read()) }
        #expect(String(bytes: q2Bytes, encoding: .utf8) == "SELECT * FROM message")
    }

    @Test func encodesEmptyQueryList() throws {
        let request = SubscribeRequest(
            requestId: 1,
            querySetId: QuerySetId(0),
            queryStrings: []
        )
        let encoded = try request.encode()
        let reader = BSATNReader(data: encoded)

        let _: UInt8 = try reader.read()   // tag
        let _: UInt32 = try reader.read()  // requestId
        let _: UInt32 = try reader.read()  // querySetId
        let queryCount: UInt32 = try reader.read()
        #expect(queryCount == 0)
    }

    @Test func handlesUnicodeInQueries() throws {
        let request = SubscribeRequest(
            requestId: 1,
            querySetId: QuerySetId(2),
            queryStrings: ["SELECT * FROM café", "SELECT * FROM 测试表"]
        )
        let encoded = try request.encode()
        let reader = BSATNReader(data: encoded)

        let _: UInt8 = try reader.read()
        let _: UInt32 = try reader.read()  // requestId
        let _: UInt32 = try reader.read()  // querySetId
        let queryCount: UInt32 = try reader.read()
        #expect(queryCount == 2)

        for expected in ["SELECT * FROM café", "SELECT * FROM 测试表"] {
            let len: UInt32 = try reader.read()
            var bytes: [UInt8] = []
            for _ in 0..<len { bytes.append(try reader.read()) }
            #expect(String(bytes: bytes, encoding: .utf8) == expected)
        }
    }

    @Test func encodesWithMaxIds() throws {
        let request = SubscribeRequest(
            requestId: UInt32.max,
            querySetId: QuerySetId(UInt32.max),
            queryStrings: ["SELECT COUNT(*) FROM test"]
        )
        let encoded = try request.encode()
        let reader = BSATNReader(data: encoded)

        let _: UInt8 = try reader.read()
        let requestId: UInt32 = try reader.read()
        let querySetId: UInt32 = try reader.read()
        #expect(requestId == UInt32.max)
        #expect(querySetId == UInt32.max)
    }

    @Test func producesConsistentEncoding() throws {
        let r1 = SubscribeRequest(requestId: 12345, querySetId: QuerySetId(1), queryStrings: ["SELECT * FROM x"])
        let r2 = SubscribeRequest(requestId: 12345, querySetId: QuerySetId(1), queryStrings: ["SELECT * FROM x"])
        #expect(try r1.encode() == r2.encode())
    }

    @Test func verifyBinaryStructure() throws {
        let request = SubscribeRequest(
            requestId: 0x12345678,
            querySetId: QuerySetId(0xABCDEF00),
            queryStrings: ["x"]
        )
        let encoded = try request.encode()

        // tag(0x00) + reqId(4) + querySetId(4) + count(4) + str_len(4) + "x"(1) = 18 bytes
        let expected: [UInt8] = [
            0x00,
            0x78, 0x56, 0x34, 0x12,
            0x00, 0xEF, 0xCD, 0xAB,
            0x01, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x00,
            0x78
        ]
        #expect(Array(encoded) == expected)
    }
}
