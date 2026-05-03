import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("OneOffQuery Response Tests")
struct OneOffQueryResponseTests {

    @Test func decodesOneOffQueryResponseCorrectly() throws {
        // Test decoding a realistic OneOffQuery response
        let writer = BSATNWriter()
        
        let messageId = Data([0x12, 0x34, 0x56, 0x78])
        let executionDuration: UInt64 = 15000  // 15ms
        
        // Write message ID as byte array
        writer.write(UInt32(messageId.count))
        writer.writeBytes(messageId)
        
        // Write error as None (tag 1)
        writer.write(UInt8(1))  // None case - no error
        
        // Write tables array with 2 tables
        writer.write(UInt32(2))  // 2 tables
        
        // First table (user)
        try writer.write("user")  // Table name with automatic length prefix
        
        // Write BsatnRowList for user table
        writer.write(UInt8(0))   // Size hint
        writer.write(UInt32(2))  // 2 offsets
        writer.write(UInt64(0))  // First row starts at offset 0
        writer.write(UInt64(10)) // Second row starts at offset 10
        writer.write(UInt32(20)) // Total data length is 20 bytes
        // Write 20 bytes of dummy row data
        for i in 0..<20 {
            writer.write(UInt8(i))
        }
        
        // Second table (message)
        try writer.write("message")  // Table name
        
        // Write BsatnRowList for message table (empty)
        writer.write(UInt8(0))   // Size hint
        writer.write(UInt32(0))  // 0 offsets (no rows)
        writer.write(UInt32(0))  // 0 data bytes
        
        // Write execution duration
        writer.write(executionDuration)
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        // Parse OneOffQueryResponse
        let response = try OneOffQueryResponse(reader: reader)
        
        // Verify all fields
        #expect(response.messageId == messageId, "Message ID should match")
        #expect(response.error == nil, "Should have no error")
        #expect(response.totalHostExecutionDuration == executionDuration, "Execution duration should match")
        #expect(response.tables.count == 2, "Should have 2 tables")
        
        // Verify first table
        let userTable = response.tables[0]
        #expect(userTable.name == "user", "First table should be 'user'")
        #expect(userTable.rows.count == 2, "User table should have 2 rows")
        #expect(userTable.rows[0].count == 10, "First row should be 10 bytes")
        #expect(userTable.rows[1].count == 10, "Second row should be 10 bytes")
        
        // Verify second table
        let messageTable = response.tables[1]
        #expect(messageTable.name == "message", "Second table should be 'message'")
        #expect(messageTable.rows.count == 0, "Message table should be empty")
        
        print("✅ OneOffQuery response decoding verified")
    }
    
    @Test func decodesWithError() throws {
        // Test response with error message
        let writer = BSATNWriter()
        
        let messageId = Data([0xAB, 0xCD])
        let errorMessage = "Table 'nonexistent' does not exist"
        
        // Write message ID
        writer.write(UInt32(messageId.count))
        writer.writeBytes(messageId)
        
        // Write error as Some (tag 0)
        writer.write(UInt8(0))  // Some case - has error
        try writer.write(errorMessage)  // Error message with length prefix
        
        // Write empty tables array
        writer.write(UInt32(0))  // 0 tables
        
        // Write execution duration
        writer.write(UInt64(5000))  // 5ms
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let response = try OneOffQueryResponse(reader: reader)
        
        #expect(response.messageId == messageId)
        #expect(response.error == errorMessage, "Should have error message")
        #expect(response.tables.isEmpty, "Should have no tables when error occurs")
        #expect(response.totalHostExecutionDuration == 5000)
    }
    
    @Test func decodesEmptyResponse() throws {
        // Test response with no tables and no error
        let writer = BSATNWriter()
        
        let _ = Data()  // Empty message ID
        
        // Write empty message ID
        writer.write(UInt32(0))
        
        // Write no error (tag 1)
        writer.write(UInt8(1))  // None case
        
        // Write empty tables array
        writer.write(UInt32(0))  // 0 tables
        
        // Write execution duration
        writer.write(UInt64(1000))  // 1ms
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let response = try OneOffQueryResponse(reader: reader)
        
        #expect(response.messageId.isEmpty, "Message ID should be empty")
        #expect(response.error == nil, "Should have no error")
        #expect(response.tables.isEmpty, "Should have no tables")
        #expect(response.totalHostExecutionDuration == 1000)
    }
    
    @Test func decodesSingleTableWithMultipleRows() throws {
        // Test response with one table containing multiple rows
        let writer = BSATNWriter()
        
        let _ = Data([0x01])
        
        // Write message ID
        writer.write(UInt32(1))
        writer.write(UInt8(0x01))
        
        // Write no error
        writer.write(UInt8(1))  // None case
        
        // Write 1 table
        writer.write(UInt32(1))
        
        // Table name
        try writer.write("test_table")
        
        // Write BsatnRowList with 3 rows
        writer.write(UInt8(0))   // Size hint
        writer.write(UInt32(3))  // 3 offsets
        writer.write(UInt64(0))  // Row 1 at offset 0
        writer.write(UInt64(5))  // Row 2 at offset 5
        writer.write(UInt64(12)) // Row 3 at offset 12
        writer.write(UInt32(20)) // Total 20 bytes of data
        
        // Write row data (20 bytes total, rows of lengths 5, 7, 8)
        for i in 0..<20 {
            writer.write(UInt8(i % 256))
        }
        
        // Write execution duration
        writer.write(UInt64(8000))  // 8ms
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let response = try OneOffQueryResponse(reader: reader)
        
        #expect(response.tables.count == 1)
        
        let table = response.tables[0]
        #expect(table.name == "test_table")
        #expect(table.rows.count == 3, "Should have 3 rows")
        #expect(table.rows[0].count == 5, "First row should be 5 bytes")
        #expect(table.rows[1].count == 7, "Second row should be 7 bytes")
        #expect(table.rows[2].count == 8, "Third row should be 8 bytes")
        
        // Verify actual row data
        #expect(Array(table.rows[0]) == [0, 1, 2, 3, 4], "First row data should match")
        #expect(Array(table.rows[1]) == [5, 6, 7, 8, 9, 10, 11], "Second row data should match")
        #expect(Array(table.rows[2]) == [12, 13, 14, 15, 16, 17, 18, 19], "Third row data should match")
    }
    
    @Test func decodesWithLargeMessageId() throws {
        // Test with large message ID
        let writer = BSATNWriter()
        
        let largeMessageId = Data(repeating: 0xFF, count: 1000)
        
        // Write large message ID
        writer.write(UInt32(largeMessageId.count))
        writer.writeBytes(largeMessageId)
        
        // Write no error
        writer.write(UInt8(1))
        
        // Write no tables
        writer.write(UInt32(0))
        
        // Write execution duration
        writer.write(UInt64(UInt64.max))  // Max duration
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let response = try OneOffQueryResponse(reader: reader)
        
        #expect(response.messageId.count == 1000, "Should handle large message ID")
        #expect(response.messageId == largeMessageId, "Large message ID should match")
        #expect(response.totalHostExecutionDuration == UInt64.max, "Should handle max execution duration")
    }
    
    @Test func decodesWithUnicodeTableNames() throws {
        // Test with unicode characters in table names
        let writer = BSATNWriter()
        
        let _ = Data([0x42])
        
        // Write message ID
        writer.write(UInt32(1))
        writer.write(UInt8(0x42))
        
        // Write no error
        writer.write(UInt8(1))
        
        // Write 2 tables with unicode names
        writer.write(UInt32(2))
        
        // First table with unicode name
        try writer.write("用户表_café")  // Unicode table name
        writer.write(UInt8(0))   // Size hint
        writer.write(UInt32(0))  // Empty BsatnRowList
        writer.write(UInt32(0))
        
        // Second table with unicode name
        try writer.write("测试_messages_🚀")  // Unicode with emoji
        writer.write(UInt8(0))   // Size hint
        writer.write(UInt32(0))  // Empty BsatnRowList
        writer.write(UInt32(0))
        
        // Write execution duration
        writer.write(UInt64(3000))
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let response = try OneOffQueryResponse(reader: reader)
        
        #expect(response.tables.count == 2)
        #expect(response.tables[0].name == "用户表_café", "Unicode table name should be preserved")
        #expect(response.tables[1].name == "测试_messages_🚀", "Unicode table name with emoji should be preserved")
    }
    
    @Test func decodesWithUnicodeErrorMessage() throws {
        // Test with unicode characters in error message
        let writer = BSATNWriter()
        
        let _ = Data([0x99])
        let unicodeError = "错误：表 'café' 不存在 🚫"
        
        // Write message ID
        writer.write(UInt32(1))
        writer.write(UInt8(0x99))
        
        // Write unicode error message
        writer.write(UInt8(0))  // Some case - has error
        try writer.write(unicodeError)
        
        // Write no tables
        writer.write(UInt32(0))
        
        // Write execution duration
        writer.write(UInt64(2000))
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let response = try OneOffQueryResponse(reader: reader)
        
        #expect(response.error == unicodeError, "Unicode error message should be preserved")
        #expect(response.tables.isEmpty, "Should have no tables when error occurs")
    }
    
    @Test func handlesMaximumValues() throws {
        // Test with maximum values and edge cases
        let writer = BSATNWriter()
        
        let _ = Data(repeating: 0xAA, count: Int(UInt16.max))
        let maxExecutionDuration = UInt64.max
        
        // Write maximum size message ID (limited to reasonable size for test)
        let testMessageId = Data(repeating: 0xAA, count: 500)
        writer.write(UInt32(testMessageId.count))
        writer.writeBytes(testMessageId)
        
        // Write no error
        writer.write(UInt8(1))
        
        // Write no tables
        writer.write(UInt32(0))
        
        // Write maximum execution duration
        writer.write(maxExecutionDuration)
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let response = try OneOffQueryResponse(reader: reader)
        
        #expect(response.messageId == testMessageId, "Should handle large message ID")
        #expect(response.totalHostExecutionDuration == maxExecutionDuration, "Should handle max execution duration")
        #expect(response.error == nil)
        #expect(response.tables.isEmpty)
        
        print("✅ OneOffQuery response with maximum values verified")
    }
}