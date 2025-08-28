import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("SubscribeApplied Response Tests")
struct SubscribeAppliedResponseTests {

    @Test func decodesSubscribeAppliedCorrectly() throws {
        // Test decoding a realistic SubscribeApplied response
        let writer = BSATNWriter()
        
        let requestId: UInt32 = 123456
        let executionDuration: UInt64 = 5000  // 5ms
        let queryId: UInt32 = 42
        
        // Write the SubscribeApplied structure
        writer.write(requestId)
        writer.write(executionDuration)
        writer.write(queryId)
        
        // Write DatabaseUpdate with single table (user)
        writer.write(UInt32(1))  // 1 table update
        
        // User table (table ID 4096)
        writer.write(UInt32(4096))  // Table ID 
        try writer.write("user")    // Table name with automatic length prefix
        writer.write(UInt64(5))     // 5 rows
        writer.write(UInt32(0))     // 0 query updates for simplicity
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        // Parse SubscribeApplied
        let subscribeApplied = try SubscribeAppliedMessage(reader: reader)
        
        // Verify all fields
        #expect(subscribeApplied.requestId == requestId, "Request ID should match")
        #expect(subscribeApplied.totalHostExecutionDurationMicros == executionDuration, "Execution duration should match")
        #expect(subscribeApplied.queryId == queryId, "Query ID should match")
        
        // Verify database update structure
        #expect(subscribeApplied.update.tableUpdates.count == 1, "Should have 1 table update")
        
        let userTable = subscribeApplied.update.tableUpdates[0]
        #expect(userTable.id == 4096, "Table should be user table (ID 4096)")
        #expect(userTable.name == "user", "Table name should be 'user'")
        #expect(userTable.numRows == 5, "User table should have 5 rows")
        
        print("✅ SubscribeApplied response decoding verified")
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
        
        let subscribeApplied = try SubscribeAppliedMessage(reader: reader)
        
        #expect(subscribeApplied.requestId == 100)
        #expect(subscribeApplied.totalHostExecutionDurationMicros == 1000)
        #expect(subscribeApplied.queryId == 1)
        #expect(subscribeApplied.update.tableUpdates.isEmpty, "Should have no table updates")
    }
    
    @Test func decodesSingleTableSubscription() throws {
        // Test response for single table subscription (typical for single subscriptions)
        let writer = BSATNWriter()
        
        writer.write(UInt32(555))    // requestId
        writer.write(UInt64(2500))   // executionDuration  
        writer.write(UInt32(999))    // queryId
        writer.write(UInt32(1))      // 1 table update
        
        // Single table (message table with ID 4097)
        writer.write(UInt32(4097))   // Message table ID
        try writer.write("message")  // Table name with automatic length prefix
        writer.write(UInt64(25))     // 25 rows
        writer.write(UInt32(0))      // 0 query updates
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let subscribeApplied = try SubscribeAppliedMessage(reader: reader)
        
        #expect(subscribeApplied.requestId == 555)
        #expect(subscribeApplied.totalHostExecutionDurationMicros == 2500)
        #expect(subscribeApplied.queryId == 999)
        #expect(subscribeApplied.update.tableUpdates.count == 1)
        
        let table = subscribeApplied.update.tableUpdates[0]
        #expect(table.id == 4097)
        #expect(table.name == "message")
        #expect(table.numRows == 25)
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
        
        let subscribeApplied = try SubscribeAppliedMessage(reader: reader)
        
        #expect(subscribeApplied.requestId == maxRequestId)
        #expect(subscribeApplied.totalHostExecutionDurationMicros == maxExecutionDuration)
        #expect(subscribeApplied.queryId == maxQueryId)
    }
    
    @Test func verifyQuickstartSingleTableStructure() throws {
        // Test the structure we expect from quickstart-chat single subscription
        let writer = BSATNWriter()
        
        writer.write(UInt32(1))      // requestId = 1 (first request)
        writer.write(UInt64(12000))  // 12ms execution time
        writer.write(UInt32(1))      // queryId = 1 (first subscription)
        writer.write(UInt32(1))      // 1 table (user only in single subscription)
        
        // User table only (in single subscription mode)
        writer.write(UInt32(4096))
        try writer.write("user")
        writer.write(UInt64(293))    // 293 users as seen in debug output
        writer.write(UInt32(0))      // No query updates in initial response
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let subscribeApplied = try SubscribeAppliedMessage(reader: reader)
        
        #expect(subscribeApplied.requestId == 1)
        #expect(subscribeApplied.queryId == 1)
        #expect(subscribeApplied.update.tableUpdates.count == 1)
        
        // Verify quickstart-chat specific table structure
        let userTable = subscribeApplied.update.tableUpdates[0]
        #expect(userTable.id == 4096, "User table should have ID 4096 (0x1000)")
        #expect(userTable.name == "user", "Should be user table")
        #expect(userTable.numRows == 293, "Should match debug output user count")
        
        print("✅ Quickstart-chat single table structure verified")
    }
    
    @Test func compareWithMultiSubscribe() throws {
        // Test that SubscribeApplied and SubscribeMultiApplied have the same structure
        let writer = BSATNWriter()
        
        // Same data for both
        writer.write(UInt32(777))
        writer.write(UInt64(3000))
        writer.write(UInt32(888))
        writer.write(UInt32(1))  // 1 table
        
        writer.write(UInt32(1000))
        try writer.write("test")
        writer.write(UInt64(10))
        writer.write(UInt32(0))
        
        let data = writer.finalize()
        
        // Parse as single SubscribeApplied
        let reader1 = BSATNReader(data: data)
        let singleApplied = try SubscribeAppliedMessage(reader: reader1)
        
        // Parse as multi SubscribeMultiApplied 
        let reader2 = BSATNReader(data: data)
        let multiApplied = try SubscribeMultiApplied(reader: reader2)
        
        // Should have the same fields
        #expect(singleApplied.requestId == multiApplied.requestId)
        #expect(singleApplied.totalHostExecutionDurationMicros == multiApplied.executionDuration)
        #expect(singleApplied.queryId == multiApplied.queryId)
        #expect(singleApplied.update.tableUpdates.count == multiApplied.update.tableUpdates.count)
        
        print("✅ SubscribeApplied vs SubscribeMultiApplied structure comparison verified")
    }
    
    @Test func decodesWithUnicodeTableName() throws {
        // Test with unicode characters in table name
        let writer = BSATNWriter()
        
        writer.write(UInt32(1))
        writer.write(UInt64(1500))
        writer.write(UInt32(2))
        writer.write(UInt32(1))  // 1 table
        
        // Table with unicode name
        writer.write(UInt32(5000))
        try writer.write("用户_table_🚀")  // Unicode table name with emoji
        writer.write(UInt64(42))
        writer.write(UInt32(0))
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        let subscribeApplied = try SubscribeAppliedMessage(reader: reader)
        
        #expect(subscribeApplied.update.tableUpdates.count == 1)
        let table = subscribeApplied.update.tableUpdates[0]
        #expect(table.name == "用户_table_🚀", "Unicode table name should be preserved")
        #expect(table.numRows == 42)
        
        print("✅ Unicode table name handling verified")
    }
}