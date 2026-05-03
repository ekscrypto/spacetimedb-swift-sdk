import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("CallReducer Request Tests")
struct CallReducerRequestTests {

    @Test func encodesCallReducerRequestCorrectly() throws {
        // Wire: tag (0x03) + request_id (u32) + flags (u8) + reducer (string) + args (bytes).
        let request = CallReducerRequest(
            reducer: "send_message",
            arguments: Data([0x01, 0x02, 0x03, 0x04]),
            requestId: 123_456_789,
            flags: .default
        )
        let encoded = try request.encode()
        let reader = BSATNReader(data: encoded)

        let messageTag: UInt8 = try reader.read()
        #expect(messageTag == Tags.ClientMessage.callReducer.rawValue,
                "Message tag should be CallReducer (0x03)")

        let requestId: UInt32 = try reader.read()
        #expect(requestId == 123_456_789)

        let flags: UInt8 = try reader.read()
        #expect(flags == CallReducerFlags.default.rawValue)

        let reducerNameLength: UInt32 = try reader.read()
        #expect(reducerNameLength == UInt32("send_message".utf8.count))
        var reducerBytes: [UInt8] = []
        for _ in 0..<reducerNameLength { reducerBytes.append(try reader.read()) }
        #expect(String(bytes: reducerBytes, encoding: .utf8) == "send_message")

        let argsLength: UInt32 = try reader.read()
        #expect(argsLength == 4)
        var argsBytes: [UInt8] = []
        for _ in 0..<argsLength { argsBytes.append(try reader.read()) }
        #expect(argsBytes == [0x01, 0x02, 0x03, 0x04])
    }

    @Test func encodesWithEmptyArguments() throws {
        let request = CallReducerRequest(
            reducer: "no_args_reducer",
            arguments: Data(),
            requestId: 1,
            flags: .default
        )
        let encoded = try request.encode()
        let reader = BSATNReader(data: encoded)

        let _: UInt8 = try reader.read()  // message tag
        let requestId: UInt32 = try reader.read()
        let flags: UInt8 = try reader.read()
        #expect(requestId == 1)
        #expect(flags == 0)

        let reducerNameLength: UInt32 = try reader.read()
        for _ in 0..<reducerNameLength { let _: UInt8 = try reader.read() }
        let argsLength: UInt32 = try reader.read()
        #expect(argsLength == 0)
    }

    @Test func encodesWithLargeArguments() throws {
        let largeArgs = Data(repeating: 0xFF, count: 1000)
        let request = CallReducerRequest(
            reducer: "large_reducer",
            arguments: largeArgs,
            requestId: 999,
            flags: .default
        )
        let encoded = try request.encode()
        let reader = BSATNReader(data: encoded)

        let _: UInt8 = try reader.read()  // tag
        let requestId: UInt32 = try reader.read()
        let _: UInt8 = try reader.read()  // flags
        #expect(requestId == 999)

        let reducerNameLength: UInt32 = try reader.read()
        for _ in 0..<reducerNameLength { let _: UInt8 = try reader.read() }

        let argsLength: UInt32 = try reader.read()
        #expect(argsLength == 1000)
        for _ in 0..<argsLength {
            let byte: UInt8 = try reader.read()
            #expect(byte == 0xFF)
        }
    }

    @Test func encodesWithUnicodeReducerName() throws {
        let unicodeReducer = "测试_reducer_café"
        let request = CallReducerRequest(
            reducer: unicodeReducer,
            arguments: Data([0x42]),
            requestId: 12345,
            flags: .default
        )
        let encoded = try request.encode()
        let reader = BSATNReader(data: encoded)

        let _: UInt8 = try reader.read()  // tag
        let _: UInt32 = try reader.read()  // requestId
        let _: UInt8 = try reader.read()  // flags

        let reducerNameLength: UInt32 = try reader.read()
        var reducerBytes: [UInt8] = []
        for _ in 0..<reducerNameLength { reducerBytes.append(try reader.read()) }
        #expect(String(bytes: reducerBytes, encoding: .utf8) == unicodeReducer)
    }

    @Test func verifyBinaryStructure() throws {
        // Exact byte verification for known input.
        let request = CallReducerRequest(
            reducer: "test",
            arguments: Data([0xAB, 0xCD]),
            requestId: 0x12345678,
            flags: .default
        )
        let encoded = try request.encode()

        // tag(0x03) + reqId(4 le) + flags(1) + reducer_len(4) + "test"(4) + args_len(4) + args(2) = 20 bytes
        let expected: [UInt8] = [
            0x03,                     // tag
            0x78, 0x56, 0x34, 0x12,   // requestId 0x12345678 little-endian
            0x00,                     // flags Default
            0x04, 0x00, 0x00, 0x00,   // reducer name length = 4
            0x74, 0x65, 0x73, 0x74,   // "test"
            0x02, 0x00, 0x00, 0x00,   // args length = 2
            0xAB, 0xCD                // args
        ]
        #expect(Array(encoded) == expected)
    }
}
