import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("SubscribeApplied Response Tests (v2)")
struct SubscribeAppliedResponseTests {

    /// v2 wire shape: request_id (u32) + query_set_id (u32) + rows: QueryRows.
    /// QueryRows = u32 table_count + [SingleTableRows]
    /// SingleTableRows = string table_name + BsatnRowList
    /// BsatnRowList = u8 size_hint + (FixedSize(u16) | RowOffsets(u32 count + count*u64)) + u32 size + bytes
    private static func writeEmptyRowList(_ writer: BSATNWriter) {
        writer.write(UInt8(1))      // hint tag = RowOffsets
        writer.write(UInt32(0))     // 0 offsets
        writer.write(UInt32(0))     // 0 data bytes
    }

    @Test func decodesSubscribeAppliedCorrectly() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(123_456))  // requestId
        writer.write(UInt32(42))       // querySetId

        // QueryRows with one table ("user", no rows)
        writer.write(UInt32(1))
        try writer.write("user")
        Self.writeEmptyRowList(writer)

        let reader = BSATNReader(data: writer.finalize())
        let msg = try SubscribeAppliedMessage(reader: reader)

        #expect(msg.requestId == 123_456)
        #expect(msg.querySetId.id == 42)
        #expect(msg.rows.tables.count == 1)
        #expect(msg.rows.tables[0].tableName == "user")
        #expect(msg.rows.tables[0].rows.rows.isEmpty)
    }

    @Test func decodesEmptyQueryRows() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(100))
        writer.write(UInt32(1))
        writer.write(UInt32(0))   // zero tables

        let reader = BSATNReader(data: writer.finalize())
        let msg = try SubscribeAppliedMessage(reader: reader)
        #expect(msg.rows.tables.isEmpty)
    }

    @Test func decodesMultipleTables() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(1))
        writer.write(UInt32(99))

        writer.write(UInt32(2))
        try writer.write("user")
        Self.writeEmptyRowList(writer)
        try writer.write("message")
        Self.writeEmptyRowList(writer)

        let reader = BSATNReader(data: writer.finalize())
        let msg = try SubscribeAppliedMessage(reader: reader)
        #expect(msg.rows.tables.count == 2)
        #expect(msg.rows.tables.map(\.tableName) == ["user", "message"])
    }

    @Test func decodesUnicodeTableName() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(1))
        writer.write(UInt32(2))
        writer.write(UInt32(1))
        try writer.write("用户_table_🚀")
        Self.writeEmptyRowList(writer)

        let reader = BSATNReader(data: writer.finalize())
        let msg = try SubscribeAppliedMessage(reader: reader)
        #expect(msg.rows.tables[0].tableName == "用户_table_🚀")
    }

    @Test func handlesMaxIds() throws {
        let writer = BSATNWriter()
        writer.write(UInt32.max)
        writer.write(UInt32.max)
        writer.write(UInt32(0))

        let reader = BSATNReader(data: writer.finalize())
        let msg = try SubscribeAppliedMessage(reader: reader)
        #expect(msg.requestId == UInt32.max)
        #expect(msg.querySetId.id == UInt32.max)
    }

    @Test func decodesFixedSizeRowList() throws {
        // Three 4-byte rows in FixedSize encoding.
        let writer = BSATNWriter()
        writer.write(UInt32(1))    // requestId
        writer.write(UInt32(0))    // querySetId
        writer.write(UInt32(1))    // table count
        try writer.write("user")
        writer.write(UInt8(0))     // hint tag = FixedSize
        writer.write(UInt16(4))    // each row 4 bytes
        writer.write(UInt32(12))   // 12 bytes of data
        writer.writeBytes(Data([
            0x01, 0x02, 0x03, 0x04,
            0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0x0C,
        ]))

        let reader = BSATNReader(data: writer.finalize())
        let msg = try SubscribeAppliedMessage(reader: reader)
        let rows = msg.rows.tables[0].rows.rows
        #expect(rows.count == 3)
        #expect(Array(rows[0]) == [0x01, 0x02, 0x03, 0x04])
        #expect(Array(rows[1]) == [0x05, 0x06, 0x07, 0x08])
        #expect(Array(rows[2]) == [0x09, 0x0A, 0x0B, 0x0C])
    }
}
