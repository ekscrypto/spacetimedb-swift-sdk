import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("UnsubscribeMultiApplied Response Tests")
struct UnsubscribeMultiAppliedResponseTests {

    @Test func decodesUnsubscribeMultiAppliedCorrectly() throws {
        // Test decoding a realistic UnsubscribeMultiApplied response
        let writer = BSATNWriter()
        
        let requestId: UInt32 = 987654
        let executionDuration: UInt64 = 2500  // 2.5ms
        let queryId: UInt32 = 123
        
        // Write the UnsubscribeMultiApplied structure
        writer.write(requestId)
        writer.write(executionDuration)
        writer.write(queryId)
        
        // Write DatabaseUpdate with cleanup data (tables being unsubscribed from)
        writer.write(UInt32(2))  // 2 table updates showing final state
        
        // User table (showing users being removed from client cache)
        writer.write(UInt32(4096))  // Table ID 
        try writer.write("user")    // Table name with automatic length prefix
        writer.write(UInt64(0))     // 0 rows remaining after unsubscribe
        writer.write(UInt32(1))     // 1 query update showing deletions
        
        // Add a simple CompressibleQueryUpdate (uncompressed)
        writer.write(UInt8(0))      // Uncompressed tag
        
        // QueryUpdate with deletions (users being removed from cache)
        // Deletes BsatnRowList - tag 1 means "Some" (has data)
        writer.write(UInt8(1))      // Has delete data
        writer.write(UInt32(0))     // 0 offsets (no actual row data in test)
        writer.write(UInt32(0))     // 0 data bytes
        
        // Inserts BsatnRowList - tag 0 means "None" (no data)
        writer.write(UInt8(0))      // No insert data
        
        // Message table
        writer.write(UInt32(4097))  // Table ID
        try writer.write("message") // Table name with automatic length prefix
        writer.write(UInt64(0))     // 0 rows remaining
        writer.write(UInt32(1))     // 1 query update
        
        // Another CompressibleQueryUpdate for message table
        writer.write(UInt8(0))      // Uncompressed tag
        
        // QueryUpdate with deletions
        writer.write(UInt8(1))      // Has delete data
        writer.write(UInt32(0))     // 0 offsets
        writer.write(UInt32(0))     // 0 data bytes
        
        writer.write(UInt8(0))      // No insert data
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        // Parse UnsubscribeMultiApplied
        let unsubscribeMultiApplied = try UnsubscribeMultiAppliedMessage(reader: reader)
        
        // Verify all fields
        #expect(unsubscribeMultiApplied.requestId == requestId, "Request ID should match")
        #expect(unsubscribeMultiApplied.totalHostExecutionDurationMicros == executionDuration, "Execution duration should match")
        #expect(unsubscribeMultiApplied.queryId == queryId, "Query ID should match")
        
        // Verify database update structure
        #expect(unsubscribeMultiApplied.update.tableUpdates.count == 2, "Should have 2 table updates")
        
        let userTable = unsubscribeMultiApplied.update.tableUpdates[0]
        #expect(userTable.id == 4096, "First table should be user table (ID 4096)")
        #expect(userTable.name == "user", "First table name should be 'user'")
        #expect(userTable.numRows == 0, "User table should have 0 rows after unsubscribe")
        
        let messageTable = unsubscribeMultiApplied.update.tableUpdates[1]
        #expect(messageTable.id == 4097, "Second table should be message table (ID 4097)")
        #expect(messageTable.name == "message", "Second table name should be 'message'")
        #expect(messageTable.numRows == 0, "Message table should have 0 rows after unsubscribe")
        
        print("✅ UnsubscribeMultiApplied response decoding verified")
    }
    
    @Test func decodesEmptyUnsubscribeResponse() throws {
        // Test response with minimal data (no actual table updates)
        let writer = BSATNWriter()
        
        writer.write(UInt32(200))    // requestId
        writer.write(UInt64(500))    // executionDuration (0.5ms)
        writer.write(UInt32(10))     // queryId
        writer.write(UInt32(0))      // 0 table updates (clean unsubscribe)
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let unsubscribeMultiApplied = try UnsubscribeMultiAppliedMessage(reader: reader)
        
        #expect(unsubscribeMultiApplied.requestId == 200)
        #expect(unsubscribeMultiApplied.totalHostExecutionDurationMicros == 500)
        #expect(unsubscribeMultiApplied.queryId == 10)
        #expect(unsubscribeMultiApplied.update.tableUpdates.isEmpty, "Should have no table updates for clean unsubscribe")
    }
    
    @Test func decodesSingleTableUnsubscribe() throws {
        // Test unsubscribing from a single table
        let writer = BSATNWriter()
        
        writer.write(UInt32(12345))  // requestId
        writer.write(UInt64(1200))   // executionDuration
        writer.write(UInt32(67890))  // queryId
        writer.write(UInt32(1))      // 1 table update
        
        // Single table being unsubscribed from
        writer.write(UInt32(5000))   // Custom table ID
        try writer.write("test_table") // Table name with automatic length prefix
        writer.write(UInt64(0))      // 0 rows after unsubscribe
        writer.write(UInt32(0))      // 0 query updates (simple cleanup)
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let unsubscribeMultiApplied = try UnsubscribeMultiAppliedMessage(reader: reader)
        
        #expect(unsubscribeMultiApplied.requestId == 12345)
        #expect(unsubscribeMultiApplied.queryId == 67890)
        #expect(unsubscribeMultiApplied.update.tableUpdates.count == 1)
        
        let table = unsubscribeMultiApplied.update.tableUpdates[0]
        #expect(table.id == 5000)
        #expect(table.name == "test_table")
        #expect(table.numRows == 0, "Should have 0 rows after unsubscribe")
    }
    
    @Test func handlesMaximumValues() throws {
        // Test with maximum UInt32/UInt64 values
        let writer = BSATNWriter()
        
        let maxRequestId = UInt32.max
        let maxExecutionDuration = UInt64.max
        let maxQueryId = UInt32.max
        
        writer.write(maxRequestId)
        writer.write(maxExecutionDuration)
        writer.write(maxQueryId)
        writer.write(UInt32(0))  // No tables
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let unsubscribeMultiApplied = try UnsubscribeMultiAppliedMessage(reader: reader)
        
        #expect(unsubscribeMultiApplied.requestId == maxRequestId)
        #expect(unsubscribeMultiApplied.totalHostExecutionDurationMicros == maxExecutionDuration)
        #expect(unsubscribeMultiApplied.queryId == maxQueryId)
    }
    
    @Test func verifyQuickstartUnsubscribeStructure() throws {
        // Test the structure we expect from quickstart-chat unsubscribe
        let writer = BSATNWriter()
        
        // Values matching what we saw in debug output
        writer.write(UInt32(1))      // requestId (first unsubscribe request)
        writer.write(UInt64(8000))   // 8ms execution time
        writer.write(UInt32(1))      // queryId (unsubscribing from subscription 1)
        writer.write(UInt32(2))      // 2 tables being cleaned up
        
        // User table cleanup
        writer.write(UInt32(4096))   // User table ID
        try writer.write("user")     // Table name with automatic length prefix
        writer.write(UInt64(0))      // All users removed from client cache
        writer.write(UInt32(0))      // No query updates needed
        
        // Message table cleanup  
        writer.write(UInt32(4097))   // Message table ID
        try writer.write("message")  // Table name with automatic length prefix
        writer.write(UInt64(0))      // All messages removed from client cache
        writer.write(UInt32(0))      // No query updates needed
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let unsubscribeMultiApplied = try UnsubscribeMultiAppliedMessage(reader: reader)
        
        #expect(unsubscribeMultiApplied.requestId == 1)
        #expect(unsubscribeMultiApplied.queryId == 1)
        #expect(unsubscribeMultiApplied.update.tableUpdates.count == 2)
        
        // Verify quickstart-chat specific cleanup structure
        let userTable = unsubscribeMultiApplied.update.tableUpdates.first { $0.name == "user" }
        let messageTable = unsubscribeMultiApplied.update.tableUpdates.first { $0.name == "message" }
        
        #expect(userTable != nil, "Should find user table in cleanup")
        #expect(messageTable != nil, "Should find message table in cleanup") 
        #expect(userTable?.id == 4096, "User table should have ID 4096")
        #expect(messageTable?.id == 4097, "Message table should have ID 4097")
        #expect(userTable?.numRows == 0, "User table should be cleared after unsubscribe")
        #expect(messageTable?.numRows == 0, "Message table should be cleared after unsubscribe")
        
        print("✅ Quickstart-chat unsubscribe structure verified")
    }
}