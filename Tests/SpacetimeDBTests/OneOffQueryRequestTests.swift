import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("OneOffQuery Request Tests")
struct OneOffQueryRequestTests {

    @Test func encodesOneOffQueryRequestCorrectly() throws {
        // Test encoding of OneOffQuery request matches expected binary format
        let messageId = Data([0x12, 0x34, 0x56, 0x78])
        let queryString = "SELECT * FROM user WHERE id = 42"
        
        let request = OneOffQueryRequest(messageId: messageId, queryString: queryString)
        let encoded = try request.encode()
        
        // Parse the encoded data to verify structure
        let reader = BSATNReader(data: encoded)
        
        // Should start with OneOffQuery message tag
        let messageTag: UInt8 = try reader.read()
        #expect(messageTag == Tags.ClientMessage.oneOffQuery.rawValue, "Message tag should be OneOffQuery (0x02)")
        
        // Read message ID array length and bytes
        let messageIdLength: UInt32 = try reader.read()
        #expect(messageIdLength == 4, "Message ID should be 4 bytes")
        
        var messageIdBytes: [UInt8] = []
        for _ in 0..<messageIdLength {
            messageIdBytes.append(try reader.read())
        }
        #expect(messageIdBytes == [0x12, 0x34, 0x56, 0x78], "Message ID should match")
        
        // Read query string array length and bytes
        let queryLength: UInt32 = try reader.read()
        let expectedQueryLength = UInt32(queryString.utf8.count)
        #expect(queryLength == expectedQueryLength, "Query string length should be \(expectedQueryLength) bytes")
        
        var queryBytes: [UInt8] = []
        for _ in 0..<queryLength {
            queryBytes.append(try reader.read())
        }
        let decodedQuery = String(bytes: queryBytes, encoding: .utf8)
        #expect(decodedQuery == queryString, "Query string should match")
        
        print("✅ OneOffQuery request encoding verified")
    }
    
    @Test func encodesWithEmptyMessageId() throws {
        // Test with empty message ID
        let request = OneOffQueryRequest(messageId: Data(), queryString: "SELECT 1")
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        // Skip message tag
        let _: UInt8 = try reader.read()
        
        // Should have 0-length message ID
        let messageIdLength: UInt32 = try reader.read()
        #expect(messageIdLength == 0, "Should have 0-length message ID")
        
        // Query string should still be present
        let queryLength: UInt32 = try reader.read()
        #expect(queryLength == 8, "Query 'SELECT 1' should be 8 bytes")
        
        var queryBytes: [UInt8] = []
        for _ in 0..<queryLength {
            queryBytes.append(try reader.read())
        }
        let query = String(bytes: queryBytes, encoding: .utf8)
        #expect(query == "SELECT 1")
    }
    
    @Test func encodesWithLargeMessageId() throws {
        // Test with large message ID
        let largeMessageId = Data(repeating: 0xAB, count: 256)
        let request = OneOffQueryRequest(messageId: largeMessageId, queryString: "SELECT * FROM large_table")
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        // Skip message tag
        let _: UInt8 = try reader.read()
        
        // Verify large message ID
        let messageIdLength: UInt32 = try reader.read()
        #expect(messageIdLength == 256, "Should have 256-byte message ID")
        
        for _ in 0..<messageIdLength {
            let byte: UInt8 = try reader.read()
            #expect(byte == 0xAB, "All message ID bytes should be 0xAB")
        }
        
        // Query should still be encoded properly
        let queryLength: UInt32 = try reader.read()
        var queryBytes: [UInt8] = []
        for _ in 0..<queryLength {
            queryBytes.append(try reader.read())
        }
        let query = String(bytes: queryBytes, encoding: .utf8)
        #expect(query == "SELECT * FROM large_table")
    }
    
    @Test func encodesWithUnicodeQuery() throws {
        // Test with unicode characters in query
        let messageId = Data([0x01])
        let unicodeQuery = "SELECT * FROM café WHERE name = '测试用户'"
        
        let request = OneOffQueryRequest(messageId: messageId, queryString: unicodeQuery)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        // Skip message tag and message ID
        let _: UInt8 = try reader.read()
        let messageIdLength: UInt32 = try reader.read()
        for _ in 0..<messageIdLength {
            let _: UInt8 = try reader.read()
        }
        
        // Read unicode query
        let queryLength: UInt32 = try reader.read()
        var queryBytes: [UInt8] = []
        for _ in 0..<queryLength {
            queryBytes.append(try reader.read())
        }
        let decodedQuery = String(bytes: queryBytes, encoding: .utf8)
        #expect(decodedQuery == unicodeQuery, "Unicode query should be preserved")
    }
    
    @Test func encodesComplexQuery() throws {
        // Test with a complex SQL query
        let messageId = Data([0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA])
        let complexQuery = """
        SELECT u.name, m.content, m.sent 
        FROM user u 
        JOIN message m ON u.id = m.sender_id 
        WHERE u.created > '2024-01-01' 
        ORDER BY m.sent DESC 
        LIMIT 100
        """
        
        let request = OneOffQueryRequest(messageId: messageId, queryString: complexQuery)
        let encoded = try request.encode()
        
        let reader = BSATNReader(data: encoded)
        
        // Verify message tag
        let messageTag: UInt8 = try reader.read()
        #expect(messageTag == Tags.ClientMessage.oneOffQuery.rawValue)
        
        // Verify message ID
        let messageIdLength: UInt32 = try reader.read()
        #expect(messageIdLength == 6)
        
        var messageIdBytes: [UInt8] = []
        for _ in 0..<messageIdLength {
            messageIdBytes.append(try reader.read())
        }
        #expect(messageIdBytes == [0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA])
        
        // Verify query
        let queryLength: UInt32 = try reader.read()
        var queryBytes: [UInt8] = []
        for _ in 0..<queryLength {
            queryBytes.append(try reader.read())
        }
        let decodedQuery = String(bytes: queryBytes, encoding: .utf8)
        #expect(decodedQuery == complexQuery, "Complex query should match exactly")
    }
    
    @Test func producesConsistentEncoding() throws {
        // Test that same inputs produce same output (deterministic)
        let messageId = Data([0x12, 0x34])
        let query = "SELECT COUNT(*) FROM messages"
        
        let request1 = OneOffQueryRequest(messageId: messageId, queryString: query)
        let request2 = OneOffQueryRequest(messageId: messageId, queryString: query)
        
        let encoded1 = try request1.encode()
        let encoded2 = try request2.encode()
        
        #expect(encoded1 == encoded2, "Same inputs should produce identical encodings")
    }
    
    @Test func verifyBinaryStructure() throws {
        // Test the exact binary structure for simple known values
        let messageId = Data([0x01, 0x02])
        let query = "test"
        
        let request = OneOffQueryRequest(messageId: messageId, queryString: query)
        let encoded = try request.encode()
        
        let actualBytes = Array(encoded)
        
        // Verify message tag is at the start
        #expect(actualBytes[0] == 0x02, "Should start with OneOffQuery tag (0x02)")
        
        // Message ID length should be 2
        #expect(actualBytes[1] == 0x02 && actualBytes[2] == 0x00 && actualBytes[3] == 0x00 && actualBytes[4] == 0x00, "Should have length 2 in little-endian")
        
        // Message ID bytes
        #expect(actualBytes[5] == 0x01 && actualBytes[6] == 0x02, "Should have message ID bytes")
        
        // Query length should be 4
        #expect(actualBytes[7] == 0x04 && actualBytes[8] == 0x00 && actualBytes[9] == 0x00 && actualBytes[10] == 0x00, "Should have query length 4")
        
        print("✅ OneOffQuery binary structure verified")
    }
}