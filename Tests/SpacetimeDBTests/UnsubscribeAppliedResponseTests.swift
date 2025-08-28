import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("UnsubscribeApplied Response Tests")
struct UnsubscribeAppliedResponseTests {

    @Test func decodesUnsubscribeAppliedCorrectly() throws {
        // Test decoding a realistic UnsubscribeApplied response
        let writer = BSATNWriter()
        
        let requestId: UInt32 = 987654
        let executionDuration: UInt64 = 2500  // 2.5ms
        let queryId: UInt32 = 123
        
        // Write the UnsubscribeApplied structure
        writer.write(requestId)
        writer.write(executionDuration)
        writer.write(queryId)
        
        // Write DatabaseUpdate with cleanup data (single table being unsubscribed from)
        writer.write(UInt32(1))  // 1 table update showing final state
        
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
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        // Parse UnsubscribeApplied
        let unsubscribeApplied = try UnsubscribeAppliedMessage(reader: reader)
        
        // Verify all fields
        #expect(unsubscribeApplied.requestId == requestId, "Request ID should match")
        #expect(unsubscribeApplied.totalHostExecutionDurationMicros == executionDuration, "Execution duration should match")
        #expect(unsubscribeApplied.queryId == queryId, "Query ID should match")
        
        // Verify database update structure
        #expect(unsubscribeApplied.update.tableUpdates.count == 1, "Should have 1 table update")
        
        let userTable = unsubscribeApplied.update.tableUpdates[0]
        #expect(userTable.id == 4096, "Table should be user table (ID 4096)")
        #expect(userTable.name == "user", "Table name should be 'user'")
        #expect(userTable.numRows == 0, "User table should have 0 rows after unsubscribe")
        
        print("✅ UnsubscribeApplied response decoding verified")
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
        
        let unsubscribeApplied = try UnsubscribeAppliedMessage(reader: reader)
        
        #expect(unsubscribeApplied.requestId == 200)
        #expect(unsubscribeApplied.totalHostExecutionDurationMicros == 500)
        #expect(unsubscribeApplied.queryId == 10)
        #expect(unsubscribeApplied.update.tableUpdates.isEmpty, "Should have no table updates for clean unsubscribe")
    }
    
    @Test func decodesSingleTableUnsubscribe() throws {
        // Test unsubscribing from a single table (typical for single subscriptions)
        let writer = BSATNWriter()
        
        writer.write(UInt32(12345))  // requestId
        writer.write(UInt64(1200))   // executionDuration
        writer.write(UInt32(67890))  // queryId
        writer.write(UInt32(1))      // 1 table update
        
        // Single table being unsubscribed from
        writer.write(UInt32(4097))   // Message table ID
        try writer.write("message")  // Table name with automatic length prefix
        writer.write(UInt64(0))      // 0 rows after unsubscribe
        writer.write(UInt32(0))      // 0 query updates (simple cleanup)
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let unsubscribeApplied = try UnsubscribeAppliedMessage(reader: reader)
        
        #expect(unsubscribeApplied.requestId == 12345)
        #expect(unsubscribeApplied.queryId == 67890)
        #expect(unsubscribeApplied.update.tableUpdates.count == 1)
        
        let table = unsubscribeApplied.update.tableUpdates[0]
        #expect(table.id == 4097)
        #expect(table.name == "message")
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
        
        let unsubscribeApplied = try UnsubscribeAppliedMessage(reader: reader)
        
        #expect(unsubscribeApplied.requestId == maxRequestId)
        #expect(unsubscribeApplied.totalHostExecutionDurationMicros == maxExecutionDuration)
        #expect(unsubscribeApplied.queryId == maxQueryId)
    }
    
    @Test func verifyQuickstartSingleUnsubscribeStructure() throws {
        // Test the structure we expect from quickstart-chat single unsubscribe
        let writer = BSATNWriter()
        
        // Values matching what we saw in debug output for single subscriptions
        writer.write(UInt32(1))      // requestId (first unsubscribe request)
        writer.write(UInt64(6000))   // 6ms execution time
        writer.write(UInt32(1))      // queryId (unsubscribing from subscription 1)
        writer.write(UInt32(1))      // 1 table being cleaned up (user only)
        
        // User table cleanup (single subscription)
        writer.write(UInt32(4096))   // User table ID
        try writer.write("user")     // Table name with automatic length prefix
        writer.write(UInt64(0))      // All users removed from client cache
        writer.write(UInt32(0))      // No query updates needed
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let unsubscribeApplied = try UnsubscribeAppliedMessage(reader: reader)
        
        #expect(unsubscribeApplied.requestId == 1)
        #expect(unsubscribeApplied.queryId == 1)
        #expect(unsubscribeApplied.update.tableUpdates.count == 1)
        
        // Verify quickstart-chat specific cleanup structure
        let userTable = unsubscribeApplied.update.tableUpdates[0]
        #expect(userTable.id == 4096, "User table should have ID 4096")
        #expect(userTable.name == "user", "Should find user table in cleanup")
        #expect(userTable.numRows == 0, "User table should be cleared after unsubscribe")
        
        print("✅ Quickstart-chat single unsubscribe structure verified")
    }
    
    @Test func compareWithMultiUnsubscribe() throws {
        // Test that UnsubscribeApplied and UnsubscribeMultiApplied have the same structure
        let writer = BSATNWriter()
        
        // Same data for both
        writer.write(UInt32(555))
        writer.write(UInt64(1500))
        writer.write(UInt32(777))
        writer.write(UInt32(1))  // 1 table
        
        writer.write(UInt32(2000))
        try writer.write("test_table")
        writer.write(UInt64(0))
        writer.write(UInt32(0))
        
        let data = writer.finalize()
        
        // Parse as single UnsubscribeApplied
        let reader1 = BSATNReader(data: data)
        let singleApplied = try UnsubscribeAppliedMessage(reader: reader1)
        
        // Parse as multi UnsubscribeMultiApplied
        let reader2 = BSATNReader(data: data)
        let multiApplied = try UnsubscribeMultiAppliedMessage(reader: reader2)
        
        // Should have the same fields
        #expect(singleApplied.requestId == multiApplied.requestId)
        #expect(singleApplied.totalHostExecutionDurationMicros == multiApplied.totalHostExecutionDurationMicros)
        #expect(singleApplied.queryId == multiApplied.queryId)
        #expect(singleApplied.update.tableUpdates.count == multiApplied.update.tableUpdates.count)
        
        print("✅ UnsubscribeApplied vs UnsubscribeMultiApplied structure comparison verified")
    }
    
    @Test func decodesWithUnicodeTableName() throws {
        // Test with unicode characters in table name being unsubscribed from
        let writer = BSATNWriter()
        
        writer.write(UInt32(999))
        writer.write(UInt64(3000))
        writer.write(UInt32(888))
        writer.write(UInt32(1))  // 1 table
        
        // Table with unicode name being unsubscribed
        writer.write(UInt32(9999))
        try writer.write("消息_table_📤")  // Unicode table name with emoji
        writer.write(UInt64(0))
        writer.write(UInt32(0))
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let unsubscribeApplied = try UnsubscribeAppliedMessage(reader: reader)
        
        #expect(unsubscribeApplied.update.tableUpdates.count == 1)
        let table = unsubscribeApplied.update.tableUpdates[0]
        #expect(table.name == "消息_table_📤", "Unicode table name should be preserved")
        #expect(table.numRows == 0, "Should be cleared after unsubscribe")
        
        print("✅ Unicode table name in unsubscribe handling verified")
    }
    
    @Test func handlesSequentialUnsubscribes() throws {
        // Test multiple unsubscribe responses in sequence (typical for single subscription mode)
        let unsubscribeData = [
            (requestId: UInt32(1), queryId: UInt32(101), table: "user"),
            (requestId: UInt32(2), queryId: UInt32(102), table: "message"),
            (requestId: UInt32(3), queryId: UInt32(103), table: "custom")
        ]
        
        for (index, data) in unsubscribeData.enumerated() {
            let writer = BSATNWriter()
            
            writer.write(data.requestId)
            writer.write(UInt64(1000 + UInt64(index * 500))) // Varying execution times
            writer.write(data.queryId)
            writer.write(UInt32(1))  // 1 table each
            
            writer.write(UInt32(5000 + UInt32(index)))
            try writer.write(data.table)
            writer.write(UInt64(0))
            writer.write(UInt32(0))
            
            let encoded = writer.finalize()
            let reader = BSATNReader(data: encoded)
            
            let unsubscribeApplied = try UnsubscribeAppliedMessage(reader: reader)
            
            #expect(unsubscribeApplied.requestId == data.requestId)
            #expect(unsubscribeApplied.queryId == data.queryId)
            #expect(unsubscribeApplied.update.tableUpdates.count == 1)
            #expect(unsubscribeApplied.update.tableUpdates[0].name == data.table)
        }
        
        print("✅ Sequential unsubscribe responses verified")
    }
}