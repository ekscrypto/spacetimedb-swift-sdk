import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("Subscribe Request Tests")
struct SubscribeRequestTests {

    @Test func encodesSubscribeRequestCorrectly() throws {
        // Test encoding of Subscribe (single) request matches expected binary format
        let queries = ["SELECT * FROM user", "SELECT * FROM message"]
        let requestId: UInt32 = 123456789
        
        let request = SubscribeRequest(queries: queries, requestId: requestId)
        let encoded = try request.encode()
        
        // Parse the encoded data to verify structure
        let reader = BSATNReader(data: encoded)
        
        // Read queries count
        let queryCount: UInt32 = try reader.read()
        #expect(queryCount == 2, "Should have 2 queries")
        
        // Read first query
        let query1Length: UInt32 = try reader.read()
        let expectedQuery1Length = UInt32("SELECT * FROM user".utf8.count)
        #expect(query1Length == expectedQuery1Length, "First query length should be \(expectedQuery1Length) bytes")
        
        var query1Bytes: [UInt8] = []
        for _ in 0..<query1Length {
            query1Bytes.append(try reader.read())
        }
        let query1String = String(bytes: query1Bytes, encoding: .utf8)
        #expect(query1String == "SELECT * FROM user", "First query should match")
        
        // Read second query
        let query2Length: UInt32 = try reader.read()
        let expectedQuery2Length = UInt32("SELECT * FROM message".utf8.count)
        #expect(query2Length == expectedQuery2Length, "Second query length should be \(expectedQuery2Length) bytes")
        
        var query2Bytes: [UInt8] = []
        for _ in 0..<query2Length {
            query2Bytes.append(try reader.read())
        }
        let query2String = String(bytes: query2Bytes, encoding: .utf8)
        #expect(query2String == "SELECT * FROM message", "Second query should match")
        
        // Read requestId
        let decodedRequestId: UInt32 = try reader.read()
        #expect(decodedRequestId == requestId, "Request ID should match")
        
        print("✅ Subscribe request encoding verified")
    }
    
    @Test func encodesEmptyQueryList() throws {
        // Test edge case of empty query list
        let queries: [String] = []
        let request = SubscribeRequest(queries: queries, requestId: 1)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        // Should have 0 queries
        let queryCount: UInt32 = try reader.read()
        #expect(queryCount == 0, "Should have 0 queries")
        
        // Should still have requestId
        let requestId: UInt32 = try reader.read()
        #expect(requestId == 1)
    }
    
    @Test func encodesSingleQuery() throws {
        // Test single query case (typical for single subscriptions)
        let queries = ["SELECT * FROM user"]
        let request = SubscribeRequest(queries: queries, requestId: 100)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        let queryCount: UInt32 = try reader.read()
        #expect(queryCount == 1, "Should have 1 query")
        
        // Verify the single query
        let queryLength: UInt32 = try reader.read()
        var queryBytes: [UInt8] = []
        for _ in 0..<queryLength {
            queryBytes.append(try reader.read())
        }
        let queryString = String(bytes: queryBytes, encoding: .utf8)
        #expect(queryString == "SELECT * FROM user")
        
        let requestId: UInt32 = try reader.read()
        #expect(requestId == 100)
    }
    
    @Test func handlesUnicodeInQueries() throws {
        // Test queries with unicode characters
        let queries = ["SELECT * FROM café", "SELECT * FROM 测试表"]
        let request = SubscribeRequest(queries: queries, requestId: 1)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        let queryCount: UInt32 = try reader.read()
        #expect(queryCount == 2)
        
        // Read first query with unicode
        let query1Length: UInt32 = try reader.read()
        var query1Bytes: [UInt8] = []
        for _ in 0..<query1Length {
            query1Bytes.append(try reader.read())
        }
        let query1String = String(bytes: query1Bytes, encoding: .utf8)
        #expect(query1String == "SELECT * FROM café")
        
        // Read second query with unicode
        let query2Length: UInt32 = try reader.read()
        var query2Bytes: [UInt8] = []
        for _ in 0..<query2Length {
            query2Bytes.append(try reader.read())
        }
        let query2String = String(bytes: query2Bytes, encoding: .utf8)
        #expect(query2String == "SELECT * FROM 测试表")
    }
    
    @Test func encodesWithMaxRequestId() throws {
        // Test with maximum UInt32 request ID
        let queries = ["SELECT COUNT(*) FROM test"]
        let maxRequestId = UInt32.max
        
        let request = SubscribeRequest(queries: queries, requestId: maxRequestId)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        // Skip query data
        let queryCount: UInt32 = try reader.read()
        for _ in 0..<queryCount {
            let queryLength: UInt32 = try reader.read()
            for _ in 0..<queryLength {
                let _: UInt8 = try reader.read()
            }
        }
        
        let requestId: UInt32 = try reader.read()
        #expect(requestId == maxRequestId, "Max request ID should be encoded correctly")
    }
    
    @Test func producesConsistentEncoding() throws {
        // Test that same inputs produce same output (deterministic)
        let queries = ["SELECT * FROM consistent_test"]
        let requestId: UInt32 = 12345
        
        let request1 = SubscribeRequest(queries: queries, requestId: requestId)
        let request2 = SubscribeRequest(queries: queries, requestId: requestId)
        
        let encoded1 = try request1.encode()
        let encoded2 = try request2.encode()
        
        #expect(encoded1 == encoded2, "Same inputs should produce identical encodings")
    }
    
    @Test func verifyStructureVsMultiSubscribe() throws {
        // Test that single Subscribe has same structure as SubscribeMulti (minus the message tag)
        let queries = ["SELECT * FROM comparison"]
        let requestId: UInt32 = 999
        
        let singleRequest = SubscribeRequest(queries: queries, requestId: requestId)
        let multiRequest = SubscribeMultiRequest(queries: queries, requestId: requestId, queryId: 1)
        
        let singleEncoded = try singleRequest.encode()
        let multiEncoded = try multiRequest.encode()
        
        // Multi request should be longer by 1 byte (message tag) + 4 bytes (queryId)
        #expect(multiEncoded.count == singleEncoded.count + 5, "Multi request should be 5 bytes longer than single request")
        
        print("✅ Subscribe vs SubscribeMulti structure comparison verified")
    }
}