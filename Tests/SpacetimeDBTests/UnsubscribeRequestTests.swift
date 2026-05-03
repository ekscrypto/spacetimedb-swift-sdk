import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("Unsubscribe Request Tests")
struct UnsubscribeRequestTests {

    @Test func encodesUnsubscribeRequestCorrectly() throws {
        // Wire: tag (0x01) + request_id (u32) + query_set_id (u32) + flags (u8)
        let request = UnsubscribeRequest(
            requestId: 987_654_321,
            querySetId: QuerySetId(123),
            flags: .default
        )
        let encoded = try request.encode()
        let reader = BSATNReader(data: encoded)

        let messageTag: UInt8 = try reader.read()
        #expect(messageTag == Tags.ClientMessage.unsubscribe.rawValue,
                "Message tag should be Unsubscribe (0x01)")

        let requestId: UInt32 = try reader.read()
        #expect(requestId == 987_654_321)

        let querySetId: UInt32 = try reader.read()
        #expect(querySetId == 123)

        let flags: UInt8 = try reader.read()
        #expect(flags == UnsubscribeFlags.default.rawValue)

        #expect(reader.remainingData().isEmpty)
    }

    @Test func encodesWithSendDroppedRowsFlag() throws {
        let request = UnsubscribeRequest(
            requestId: 1,
            querySetId: QuerySetId(99),
            flags: .sendDroppedRows
        )
        let encoded = try request.encode()
        let reader = BSATNReader(data: encoded)

        let _: UInt8 = try reader.read()  // tag
        let _: UInt32 = try reader.read()  // requestId
        let _: UInt32 = try reader.read()  // querySetId
        let flags: UInt8 = try reader.read()
        #expect(flags == UnsubscribeFlags.sendDroppedRows.rawValue)
    }

    @Test func encodesWithMaxValues() throws {
        let request = UnsubscribeRequest(
            requestId: UInt32.max,
            querySetId: QuerySetId(UInt32.max),
            flags: .default
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
        let r1 = UnsubscribeRequest(requestId: 12345, querySetId: QuerySetId(67890), flags: .default)
        let r2 = UnsubscribeRequest(requestId: 12345, querySetId: QuerySetId(67890), flags: .default)
        #expect(try r1.encode() == r2.encode())
    }

    @Test func verifyBinaryStructure() throws {
        let request = UnsubscribeRequest(
            requestId: 0x12345678,
            querySetId: QuerySetId(0xABCDEF00),
            flags: .sendDroppedRows
        )
        let encoded = try request.encode()

        // tag(0x01) + reqId(4) + querySetId(4) + flags(1) = 10 bytes
        let expected: [UInt8] = [
            0x01,
            0x78, 0x56, 0x34, 0x12,
            0x00, 0xEF, 0xCD, 0xAB,
            0x01
        ]
        #expect(Array(encoded) == expected)
    }
}
