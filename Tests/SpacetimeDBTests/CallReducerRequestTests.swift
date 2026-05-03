import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("CallReducer Request Tests")
struct CallReducerRequestTests {

    @Test func encodesCallReducerRequestCorrectly() throws {
        // Test encoding of CallReducer request matches expected binary format
        let reducer = "send_message"
        let arguments = Data([0x01, 0x02, 0x03, 0x04]) // Sample binary data
        let requestId: UInt32 = 123456789
        let flags: UInt8 = 0
        
        let request = CallReducerRequest(reducer: reducer, arguments: arguments, requestId: requestId, flags: flags)
        let encoded = try request.encode()
        
        // Parse the encoded data to verify structure
        let reader = BSATNReader(data: encoded)
        
        // Should start with CallReducer message tag
        let messageTag: UInt8 = try reader.read()
        #expect(messageTag == Tags.ClientMessage.callReducer.rawValue, "Message tag should be CallReducer (0x00)")
        
        // Read reducer name length and string
        let reducerNameLength: UInt32 = try reader.read()
        let expectedReducerNameLength = UInt32("send_message".utf8.count)
        #expect(reducerNameLength == expectedReducerNameLength, "Reducer name length should be \(expectedReducerNameLength) bytes")
        
        var reducerBytes: [UInt8] = []
        for _ in 0..<reducerNameLength {
            reducerBytes.append(try reader.read())
        }
        let reducerString = String(bytes: reducerBytes, encoding: .utf8)
        #expect(reducerString == "send_message", "Reducer name should match")
        
        // Read arguments array length and data
        let argsLength: UInt32 = try reader.read()
        #expect(argsLength == 4, "Arguments should be 4 bytes")
        
        var argsBytes: [UInt8] = []
        for _ in 0..<argsLength {
            argsBytes.append(try reader.read())
        }
        #expect(argsBytes == [0x01, 0x02, 0x03, 0x04], "Arguments should match")
        
        // Read requestId
        let decodedRequestId: UInt32 = try reader.read()
        #expect(decodedRequestId == requestId, "Request ID should match")
        
        // Read flags
        let decodedFlags: UInt8 = try reader.read()
        #expect(decodedFlags == flags, "Flags should match")
        
        print("✅ CallReducer request encoding verified")
    }
    
    @Test func encodesWithEmptyArguments() throws {
        // Test CallReducer with no arguments
        let request = CallReducerRequest(reducer: "no_args_reducer", arguments: Data(), requestId: 1, flags: 0)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        // Skip message tag
        let _: UInt8 = try reader.read()
        
        // Skip reducer name
        let reducerNameLength: UInt32 = try reader.read()
        for _ in 0..<reducerNameLength {
            let _: UInt8 = try reader.read()
        }
        
        // Should have 0 arguments
        let argsLength: UInt32 = try reader.read()
        #expect(argsLength == 0, "Should have 0 arguments")
        
        let requestId: UInt32 = try reader.read()
        let flags: UInt8 = try reader.read()
        #expect(requestId == 1)
        #expect(flags == 0)
    }
    
    @Test func encodesWithLargeArguments() throws {
        // Test with large argument data
        let largeArgs = Data(repeating: 0xFF, count: 1000)
        let request = CallReducerRequest(reducer: "large_reducer", arguments: largeArgs, requestId: 999, flags: 255)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        // Skip message tag and reducer name
        let _: UInt8 = try reader.read()
        let reducerNameLength: UInt32 = try reader.read()
        for _ in 0..<reducerNameLength {
            let _: UInt8 = try reader.read()
        }
        
        // Verify large arguments
        let argsLength: UInt32 = try reader.read()
        #expect(argsLength == 1000, "Should have 1000 bytes of arguments")
        
        for _ in 0..<argsLength {
            let byte: UInt8 = try reader.read()
            #expect(byte == 0xFF, "All argument bytes should be 0xFF")
        }
        
        let requestId: UInt32 = try reader.read()
        let flags: UInt8 = try reader.read()
        #expect(requestId == 999)
        #expect(flags == 255)
    }
    
    @Test func encodesWithUnicodeReducerName() throws {
        // Test with unicode characters in reducer name
        let unicodeReducer = "测试_reducer_café"
        let request = CallReducerRequest(reducer: unicodeReducer, arguments: Data([0x42]), requestId: 12345, flags: 1)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        // Skip message tag
        let _: UInt8 = try reader.read()
        
        // Read unicode reducer name
        let reducerNameLength: UInt32 = try reader.read()
        var reducerBytes: [UInt8] = []
        for _ in 0..<reducerNameLength {
            reducerBytes.append(try reader.read())
        }
        let decodedReducer = String(bytes: reducerBytes, encoding: .utf8)
        #expect(decodedReducer == unicodeReducer, "Unicode reducer name should be preserved")
        
        // Verify rest of structure
        let argsLength: UInt32 = try reader.read()
        #expect(argsLength == 1)
        let argByte: UInt8 = try reader.read()
        #expect(argByte == 0x42)
    }
    
    @Test func handlesMaximumValues() throws {
        // Test with maximum values
        let maxRequestId = UInt32.max
        let maxFlags = UInt8.max
        
        let request = CallReducerRequest(reducer: "max_test", arguments: Data([0x00]), requestId: maxRequestId, flags: maxFlags)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        // Skip to the end fields
        let _: UInt8 = try reader.read() // message tag
        let reducerLength: UInt32 = try reader.read()
        for _ in 0..<reducerLength {
            let _: UInt8 = try reader.read()
        }
        let argsLength: UInt32 = try reader.read()
        for _ in 0..<argsLength {
            let _: UInt8 = try reader.read()
        }
        
        let requestId: UInt32 = try reader.read()
        let flags: UInt8 = try reader.read()
        
        #expect(requestId == maxRequestId, "Max request ID should be encoded correctly")
        #expect(flags == maxFlags, "Max flags should be encoded correctly")
    }
    
    @Test func verifyBinaryStructure() throws {
        // Test the exact binary structure for known values
        let request = CallReducerRequest(reducer: "test", arguments: Data([0xAB, 0xCD]), requestId: 0x12345678, flags: 0x42)
        let encoded = try request.encode()
        
        let actualBytes = Array(encoded)
        
        // Verify message tag is at the start
        #expect(actualBytes[0] == 0x00, "Should start with CallReducer tag (0x00)")
        
        // The rest is variable length due to strings, so we verify structure by parsing
        let reader = BSATNReader(data: encoded)
        let _: UInt8 = try reader.read() // tag
        
        let nameLength: UInt32 = try reader.read()
        #expect(nameLength == 4, "Reducer name 'test' should be 4 bytes")
        
        // Verify the actual parsing works end-to-end
        #expect(reader.remainingData().count > 0, "Should have remaining data to parse")
        
        print("✅ CallReducer binary structure verified")
    }
}