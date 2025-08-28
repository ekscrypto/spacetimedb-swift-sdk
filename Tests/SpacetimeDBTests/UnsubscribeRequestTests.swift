import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("Unsubscribe Request Tests")
struct UnsubscribeRequestTests {

    @Test func encodesUnsubscribeRequestCorrectly() throws {
        // Test encoding of Unsubscribe (single) request matches expected binary format
        let requestId: UInt32 = 987654321
        let queryId: UInt32 = 123
        
        let request = UnsubscribeRequest(requestId: requestId, queryId: queryId)
        let encoded = try request.encode()
        
        // Parse the encoded data to verify structure
        let reader = BSATNReader(data: encoded)
        
        // Should contain requestId and queryId in that order
        let decodedRequestId: UInt32 = try reader.read()
        #expect(decodedRequestId == requestId, "Request ID should match: expected \(requestId), got \(decodedRequestId)")
        
        let decodedQueryId: UInt32 = try reader.read()
        #expect(decodedQueryId == queryId, "Query ID should match: expected \(queryId), got \(decodedQueryId)")
        
        // Should be at end of data
        #expect(reader.remainingData().isEmpty, "Should have consumed all data")
        
        print("✅ Unsubscribe request encoding verified: requestId=\(requestId), queryId=\(queryId)")
    }
    
    @Test func encodesWithZeroIds() throws {
        // Test edge case with zero IDs
        let request = UnsubscribeRequest(requestId: 0, queryId: 0)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        let requestId: UInt32 = try reader.read()
        let queryId: UInt32 = try reader.read()
        
        #expect(requestId == 0, "Zero request ID should be handled correctly")
        #expect(queryId == 0, "Zero query ID should be handled correctly")
    }
    
    @Test func encodesWithMaxValues() throws {
        // Test with maximum UInt32 values
        let maxRequestId = UInt32.max
        let maxQueryId = UInt32.max
        
        let request = UnsubscribeRequest(requestId: maxRequestId, queryId: maxQueryId)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        let requestId: UInt32 = try reader.read()
        let queryId: UInt32 = try reader.read()
        
        #expect(requestId == maxRequestId, "Max request ID should be encoded correctly")
        #expect(queryId == maxQueryId, "Max query ID should be encoded correctly")
    }
    
    @Test func producesConsistentEncoding() throws {
        // Test that same inputs produce same output (deterministic)
        let requestId: UInt32 = 12345
        let queryId: UInt32 = 67890
        
        let request1 = UnsubscribeRequest(requestId: requestId, queryId: queryId)
        let request2 = UnsubscribeRequest(requestId: requestId, queryId: queryId)
        
        let encoded1 = try request1.encode()
        let encoded2 = try request2.encode()
        
        #expect(encoded1 == encoded2, "Same inputs should produce identical encodings")
        #expect(encoded1.count == 8, "Should be exactly 8 bytes (2 x UInt32)")
    }
    
    @Test func verifyBinaryStructure() throws {
        // Test the exact binary structure for known values
        let requestId: UInt32 = 0x12345678
        let queryId: UInt32 = 0xABCDEF00
        
        let request = UnsubscribeRequest(requestId: requestId, queryId: queryId)
        let encoded = try request.encode()
        
        #expect(encoded.count == 8, "Should be exactly 8 bytes")
        
        // Verify little-endian encoding of UInt32 values
        let expectedBytes: [UInt8] = [
            0x78, 0x56, 0x34, 0x12,  // requestId in little-endian
            0x00, 0xEF, 0xCD, 0xAB   // queryId in little-endian
        ]
        
        let actualBytes = Array(encoded)
        #expect(actualBytes == expectedBytes, "Binary encoding should match expected little-endian format")
        
        print("✅ Unsubscribe binary structure verified: \(actualBytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
    }
    
    @Test func compareWithMultiUnsubscribe() throws {
        // Test that single and multi unsubscribe have same structure (both have requestId and queryId)
        let requestId: UInt32 = 999
        let queryId: UInt32 = 111
        
        let singleRequest = UnsubscribeRequest(requestId: requestId, queryId: queryId)
        let multiRequest = UnsubscribeMultiRequest(requestId: requestId, queryId: queryId)
        
        let singleEncoded = try singleRequest.encode()
        let multiEncoded = try multiRequest.encode()
        
        // Both should have the same structure since they use the same fields
        // But the multi request uses AlgebraicValue encoding while single uses direct encoding
        #expect(singleEncoded.count == 8, "Single request should be 8 bytes")
        #expect(multiEncoded.count == 8, "Multi request should be 8 bytes")
        
        // However, the encoding method is different (AlgebraicValue vs direct)
        // So the actual bytes might be different
        
        print("✅ Single vs Multi unsubscribe structure comparison verified")
    }
    
    @Test func handlesSequentialRequests() throws {
        // Test encoding multiple sequential unsubscribe requests
        let requests = [
            UnsubscribeRequest(requestId: 1, queryId: 101),
            UnsubscribeRequest(requestId: 2, queryId: 102),
            UnsubscribeRequest(requestId: 3, queryId: 103)
        ]
        
        for (index, request) in requests.enumerated() {
            let encoded = try request.encode()
            let reader = BSATNReader(data: encoded)
            
            let requestId: UInt32 = try reader.read()
            let queryId: UInt32 = try reader.read()
            
            #expect(requestId == UInt32(index + 1), "Request ID should match sequence")
            #expect(queryId == UInt32(101 + index), "Query ID should match sequence")
        }
        
        print("✅ Sequential unsubscribe requests verified")
    }
}