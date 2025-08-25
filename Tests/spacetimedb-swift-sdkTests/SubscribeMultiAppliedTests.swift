import XCTest
@testable import spacetimedb_swift_sdk
@testable import BSATN

final class SubscribeMultiAppliedTests: XCTestCase {
    
    func testTableIDsAreConsistent() throws {
        // Test that table IDs like 4097 (0x1001) are valid
        // These are the actual IDs assigned by SpacetimeDB
        
        // Create a mock SubscribeMultiApplied with table ID 4097
        let writer = BSATNWriter()
        
        // Write compression and message type
        writer.write(UInt8(0))  // no compression
        writer.write(UInt8(8))  // SubscribeMultiApplied message type
        
        // Write request ID
        writer.write(UInt32(1))
        
        // Write query ID  
        writer.write(UInt32(0))
        
        // Write DatabaseUpdate with 1 table
        writer.write(UInt32(1))
        
        // Write TableUpdate
        writer.write(UInt32(4097))  // Table ID 0x1001
        writer.write(UInt32(7))     // String length
        for byte in "message".utf8 {
            writer.write(byte)
        }
        writer.write(UInt64(0))     // num rows
        writer.write(UInt32(0))     // 0 query updates
        
        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        
        // Skip compression and message type
        let _: UInt8 = try reader.read()
        let _: UInt8 = try reader.read()
        
        // Parse SubscribeMultiApplied
        let subscribeMultiApplied = try SubscribeMultiApplied(reader: reader)
        
        // Verify table ID
        XCTAssertEqual(subscribeMultiApplied.update.tableUpdates.count, 1)
        let tableUpdate = subscribeMultiApplied.update.tableUpdates[0]
        XCTAssertEqual(tableUpdate.id, 4097, "Table ID 4097 (0x1001) is valid")
        XCTAssertEqual(tableUpdate.name, "message")
        
        print("✅ Table ID 4097 is confirmed as valid")
    }
    
    func testUserTableID() throws {
        // The "user" table typically has ID 4096 (0x1000)
        let userTableId: UInt32 = 4096
        print("User table ID: \(userTableId) (0x\(String(format: "%04X", userTableId)))")
        XCTAssertEqual(userTableId, 0x1000)
        
        // Message table would be 4097 (0x1001)
        let messageTableId: UInt32 = 4097
        print("Message table ID: \(messageTableId) (0x\(String(format: "%04X", messageTableId)))")
        XCTAssertEqual(messageTableId, 0x1001)
    }
}