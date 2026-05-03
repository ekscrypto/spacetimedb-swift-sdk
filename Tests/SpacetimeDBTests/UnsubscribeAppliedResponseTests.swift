import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("UnsubscribeApplied Response Tests (v2)")
struct UnsubscribeAppliedResponseTests {

    /// v2 wire shape: request_id (u32) + query_set_id (u32) + rows: Option<QueryRows>.
    /// Option tag 0 = Some(QueryRows), tag 1 = None.

    private static func writeEmptyRowList(_ writer: BSATNWriter) {
        writer.write(UInt8(1))      // hint tag = RowOffsets
        writer.write(UInt32(0))     // 0 offsets
        writer.write(UInt32(0))     // 0 data bytes
    }

    @Test func decodesUnsubscribeWithoutDroppedRows() throws {
        // Default unsubscribe — Option<QueryRows> = None.
        let writer = BSATNWriter()
        writer.write(UInt32(987_654))  // requestId
        writer.write(UInt32(123))      // querySetId
        writer.write(UInt8(1))         // Option tag = None

        let reader = BSATNReader(data: writer.finalize())
        let msg = try UnsubscribeAppliedMessage(reader: reader)

        #expect(msg.requestId == 987_654)
        #expect(msg.querySetId.id == 123)
        #expect(msg.droppedRows == nil, "Default Unsubscribe should produce nil droppedRows")
    }

    @Test func decodesUnsubscribeWithDroppedRows() throws {
        // SendDroppedRows flag was set — Option<QueryRows> = Some(QueryRows).
        let writer = BSATNWriter()
        writer.write(UInt32(1))         // requestId
        writer.write(UInt32(7))         // querySetId
        writer.write(UInt8(0))          // Option tag = Some
        writer.write(UInt32(1))         // 1 table
        try writer.write("user")
        Self.writeEmptyRowList(writer)

        let reader = BSATNReader(data: writer.finalize())
        let msg = try UnsubscribeAppliedMessage(reader: reader)

        #expect(msg.droppedRows != nil)
        #expect(msg.droppedRows?.tables.count == 1)
        #expect(msg.droppedRows?.tables[0].tableName == "user")
    }

    @Test func handlesMaxValues() throws {
        let writer = BSATNWriter()
        writer.write(UInt32.max)
        writer.write(UInt32.max)
        writer.write(UInt8(1))   // None

        let reader = BSATNReader(data: writer.finalize())
        let msg = try UnsubscribeAppliedMessage(reader: reader)
        #expect(msg.requestId == UInt32.max)
        #expect(msg.querySetId.id == UInt32.max)
        #expect(msg.droppedRows == nil)
    }

    @Test func unicodeTableNameInDroppedRows() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(1))
        writer.write(UInt32(1))
        writer.write(UInt8(0))
        writer.write(UInt32(1))
        try writer.write("消息_table_📤")
        Self.writeEmptyRowList(writer)

        let reader = BSATNReader(data: writer.finalize())
        let msg = try UnsubscribeAppliedMessage(reader: reader)
        #expect(msg.droppedRows?.tables[0].tableName == "消息_table_📤")
    }
}
