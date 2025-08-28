import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("SubscribeMultiApplied Response Tests")
struct SubscribeMultiAppliedResponseTests {

    @Test func decodesSubscribeMultiAppliedCorrectly() throws {
        // Test decoding a realistic SubscribeMultiApplied response
        let writer = BSATNWriter()
        
        let requestId: UInt32 = 123456
        let executionDuration: UInt64 = 5000  // 5ms
        let queryId: UInt32 = 42
        
        // Write the SubscribeMultiApplied structure
        writer.write(requestId)
        writer.write(executionDuration)
        writer.write(queryId)
        
        // Write DatabaseUpdate with 2 tables (user and message)
        writer.write(UInt32(2))  // 2 table updates
        
        // First table (user - table ID 4096)
        writer.write(UInt32(4096))  // Table ID 
        try writer.write("user")    // Table name with automatic length prefix
        writer.write(UInt64(10))    // 10 rows
        writer.write(UInt32(0))     // 0 query updates for simplicity
        
        // Second table (message - table ID 4097)
        writer.write(UInt32(4097))  // Table ID
        try writer.write("message") // Table name with automatic length prefix
        writer.write(UInt64(5))     // 5 rows
        writer.write(UInt32(0))     // 0 query updates for simplicity
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        // Parse SubscribeMultiApplied
        let subscribeMultiApplied = try SubscribeMultiApplied(reader: reader)
        
        // Verify all fields
        #expect(subscribeMultiApplied.requestId == requestId, "Request ID should match")
        #expect(subscribeMultiApplied.executionDuration == executionDuration, "Execution duration should match")
        #expect(subscribeMultiApplied.queryId == queryId, "Query ID should match")
        
        // Verify database update structure
        #expect(subscribeMultiApplied.update.tableUpdates.count == 2, "Should have 2 table updates")
        
        let userTable = subscribeMultiApplied.update.tableUpdates[0]
        #expect(userTable.id == 4096, "First table should be user table (ID 4096)")
        #expect(userTable.name == "user", "First table name should be 'user'")
        #expect(userTable.numRows == 10, "User table should have 10 rows")
        
        let messageTable = subscribeMultiApplied.update.tableUpdates[1]
        #expect(messageTable.id == 4097, "Second table should be message table (ID 4097)")
        #expect(messageTable.name == "message", "Second table name should be 'message'")
        #expect(messageTable.numRows == 5, "Message table should have 5 rows")
        
        print("✅ SubscribeMultiApplied response decoding verified")
    }
    
    @Test func decodesEmptyDatabaseUpdate() throws {
        // Test response with no table updates
        let writer = BSATNWriter()
        
        writer.write(UInt32(100))   // requestId
        writer.write(UInt64(1000))  // executionDuration
        writer.write(UInt32(1))     // queryId
        writer.write(UInt32(0))     // 0 table updates
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let subscribeMultiApplied = try SubscribeMultiApplied(reader: reader)
        
        #expect(subscribeMultiApplied.requestId == 100)
        #expect(subscribeMultiApplied.executionDuration == 1000)
        #expect(subscribeMultiApplied.queryId == 1)
        #expect(subscribeMultiApplied.update.tableUpdates.isEmpty, "Should have no table updates")
    }
    
    @Test func decodesSingleTableUpdate() throws {
        // Test response with just one table
        let writer = BSATNWriter()
        
        writer.write(UInt32(555))    // requestId
        writer.write(UInt64(2500))   // executionDuration  
        writer.write(UInt32(999))    // queryId
        writer.write(UInt32(1))      // 1 table update
        
        // Single table (custom table with ID 8000)
        writer.write(UInt32(8000))   // Custom table ID
        try writer.write("custom_table") // Table name with automatic length prefix
        writer.write(UInt64(100))    // 100 rows
        writer.write(UInt32(0))      // 0 query updates
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let subscribeMultiApplied = try SubscribeMultiApplied(reader: reader)
        
        #expect(subscribeMultiApplied.requestId == 555)
        #expect(subscribeMultiApplied.executionDuration == 2500)
        #expect(subscribeMultiApplied.queryId == 999)
        #expect(subscribeMultiApplied.update.tableUpdates.count == 1)
        
        let table = subscribeMultiApplied.update.tableUpdates[0]
        #expect(table.id == 8000)
        #expect(table.name == "custom_table")
        #expect(table.numRows == 100)
    }
    
    @Test func handlesLargeValues() throws {
        // Test with maximum/large values
        let writer = BSATNWriter()
        
        let maxRequestId = UInt32.max
        let maxExecutionDuration = UInt64.max  
        let maxQueryId = UInt32.max
        
        writer.write(maxRequestId)
        writer.write(maxExecutionDuration)
        writer.write(maxQueryId)
        writer.write(UInt32(0))  // No tables for simplicity
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let subscribeMultiApplied = try SubscribeMultiApplied(reader: reader)
        
        #expect(subscribeMultiApplied.requestId == maxRequestId)
        #expect(subscribeMultiApplied.executionDuration == maxExecutionDuration)
        #expect(subscribeMultiApplied.queryId == maxQueryId)
    }
    
    @Test func verifyQuickstartTablesStructure() throws {
        // Test the specific table structure from quickstart-chat
        let writer = BSATNWriter()
        
        writer.write(UInt32(1))      // requestId = 1 (common in tests)
        writer.write(UInt64(15000))  // 15ms execution time
        writer.write(UInt32(1))      // queryId = 1 (first subscription)
        writer.write(UInt32(2))      // 2 tables (user and message)
        
        // User table (ID 4096 = 0x1000)
        writer.write(UInt32(4096))
        try writer.write("user")
        writer.write(UInt64(293))    // 293 users as seen in debug output
        writer.write(UInt32(0))      // No query updates in initial response
        
        // Message table (ID 4097 = 0x1001) 
        writer.write(UInt32(4097))
        writer.write(UInt32(7))
        for byte in "message".utf8 {
            writer.write(byte)
        }
        writer.write(UInt64(54))     // 54 messages as seen in debug output
        writer.write(UInt32(0))      // No query updates in initial response
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let subscribeMultiApplied = try SubscribeMultiApplied(reader: reader)
        
        #expect(subscribeMultiApplied.requestId == 1)
        #expect(subscribeMultiApplied.queryId == 1)
        #expect(subscribeMultiApplied.update.tableUpdates.count == 2)
        
        // Verify quickstart-chat specific table structure
        let userTable = subscribeMultiApplied.update.tableUpdates.first { $0.name == "user" }
        let messageTable = subscribeMultiApplied.update.tableUpdates.first { $0.name == "message" }
        
        #expect(userTable != nil, "Should find user table")
        #expect(messageTable != nil, "Should find message table")
        #expect(userTable?.id == 4096, "User table should have ID 4096 (0x1000)")
        #expect(messageTable?.id == 4097, "Message table should have ID 4097 (0x1001)")
        #expect(userTable?.numRows == 293, "Should match debug output user count")
        #expect(messageTable?.numRows == 54, "Should match debug output message count")
        
        print("✅ Quickstart-chat table structure verified")
    }
}