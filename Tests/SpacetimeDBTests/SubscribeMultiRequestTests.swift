import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("SubscribeMulti Request Tests")
struct SubscribeMultiRequestTests {

    @Test func encodesSubscribeMultiRequestCorrectly() throws {
        // Test encoding of SubscribeMulti request matches expected binary format
        let queries = ["SELECT * FROM user", "SELECT * FROM message"]
        let requestId: UInt32 = 123456789
        let queryId: UInt32 = 42
        
        let request = SubscribeMultiRequest(queries: queries, requestId: requestId, queryId: queryId)
        let encoded = try request.encode()
        
        // Parse the encoded data to verify structure
        let reader = BSATNReader(data: encoded)
        
        // Should start with SubscribeMulti message tag
        let messageTag: UInt8 = try reader.read()
        #expect(messageTag == Tags.ClientMessage.subscribeMulti.rawValue, "Message tag should be SubscribeMulti (0x04)")
        
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
        
        // Read queryId
        let decodedQueryId: UInt32 = try reader.read()
        #expect(decodedQueryId == queryId, "Query ID should match")
        
        print("✅ SubscribeMulti request encoding verified")
    }
    
    @Test func encodesEmptyQueryList() throws {
        // Test edge case of empty query list
        let queries: [String] = []
        let request = SubscribeMultiRequest(queries: queries, requestId: 1, queryId: 1)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        // Skip message tag
        let _: UInt8 = try reader.read()
        
        // Should have 0 queries
        let queryCount: UInt32 = try reader.read()
        #expect(queryCount == 0, "Should have 0 queries")
        
        // Should still have requestId and queryId
        let requestId: UInt32 = try reader.read()
        let queryId: UInt32 = try reader.read()
        #expect(requestId == 1)
        #expect(queryId == 1)
    }
    
    @Test func encodesSingleQuery() throws {
        // Test single query case
        let queries = ["SELECT * FROM user"]
        let request = SubscribeMultiRequest(queries: queries, requestId: 100, queryId: 200)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        // Skip message tag
        let _: UInt8 = try reader.read()
        
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
        let queryId: UInt32 = try reader.read()
        #expect(requestId == 100)
        #expect(queryId == 200)
    }
    
    @Test func handlesUnicodeInQueries() throws {
        // Test queries with unicode characters
        let queries = ["SELECT * FROM café", "SELECT * FROM 测试表"]
        let request = SubscribeMultiRequest(queries: queries, requestId: 1, queryId: 2)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        // Skip message tag
        let _: UInt8 = try reader.read()
        
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
}