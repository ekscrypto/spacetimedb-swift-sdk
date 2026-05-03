import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("TransactionUpdate Tests (v2)")
struct TransactionUpdateTests {

    /// v2 TransactionUpdate is just a list of QuerySetUpdates with row diffs.
    /// All v1 metadata (status, timestamp, callerIdentity, callerConnectionId,
    /// reducerCall, energyQuanta, executionDuration) is gone — that information
    /// rides with ReducerResult instead. v2 TransactionUpdate is sent only for
    /// transactions that did NOT originate from this client.
    ///
    /// QuerySetUpdate = query_set_id (u32) + tables ([TableUpdate])
    /// TableUpdate    = table_name (string) + rows ([TableUpdateRows])
    /// TableUpdateRows = sum
    ///   tag 0 = PersistentTable { inserts: BsatnRowList, deletes: BsatnRowList }
    ///   tag 1 = EventTable { events: BsatnRowList }
    /// BsatnRowList = u8 hint + (FixedSize(u16) | RowOffsets(u32 + count*u64)) + u32 size + bytes

    private static func writeEmptyRowList(_ w: BSATNWriter) {
        w.write(UInt8(1))      // RowOffsets variant
        w.write(UInt32(0))     // 0 offsets
        w.write(UInt32(0))     // 0 data bytes
    }

    @Test func decodesEmptyTransactionUpdate() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(0))    // 0 query sets

        let reader = BSATNReader(data: writer.finalize())
        let update = try TransactionUpdate(reader: reader)
        #expect(update.querySets.isEmpty)
    }

    @Test func decodesSingleQuerySetWithEmptyPersistentTable() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(1))         // 1 query set
        writer.write(UInt32(7))         // querySetId

        writer.write(UInt32(1))         // 1 table
        try writer.write("user")

        writer.write(UInt32(1))         // 1 row-set variant
        writer.write(UInt8(0))          // PersistentTable
        Self.writeEmptyRowList(writer)  // inserts (FIRST in v2)
        Self.writeEmptyRowList(writer)  // deletes

        let reader = BSATNReader(data: writer.finalize())
        let update = try TransactionUpdate(reader: reader)
        #expect(update.querySets.count == 1)
        #expect(update.querySets[0].querySetId.id == 7)
        #expect(update.querySets[0].tables[0].tableName == "user")

        let rows = update.querySets[0].tables[0].rows[0]
        if case .persistent(let inserts, let deletes) = rows {
            #expect(inserts.rows.isEmpty)
            #expect(deletes.rows.isEmpty)
        } else {
            Issue.record("Expected .persistent variant")
        }
    }

    @Test func decodesEventTable() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(1))
        writer.write(UInt32(2))         // querySetId

        writer.write(UInt32(1))
        try writer.write("audit_event")

        writer.write(UInt32(1))         // 1 row-set variant
        writer.write(UInt8(1))          // EventTable
        Self.writeEmptyRowList(writer)

        let reader = BSATNReader(data: writer.finalize())
        let update = try TransactionUpdate(reader: reader)
        let rows = update.querySets[0].tables[0].rows[0]
        if case .event(let events) = rows {
            #expect(events.rows.isEmpty)
        } else {
            Issue.record("Expected .event variant")
        }
    }

    @Test func decodesPersistentTableWithFixedSizeRows() throws {
        // Two 4-byte inserts, no deletes.
        let writer = BSATNWriter()
        writer.write(UInt32(1))
        writer.write(UInt32(0))                 // querySetId

        writer.write(UInt32(1))
        try writer.write("rows")

        writer.write(UInt32(1))
        writer.write(UInt8(0))                  // PersistentTable

        // inserts (FIRST per v2): 2 rows of 4 bytes each
        writer.write(UInt8(0))                  // FixedSize variant
        writer.write(UInt16(4))
        writer.write(UInt32(8))
        writer.writeBytes(Data([0xAA, 0xBB, 0xCC, 0xDD,
                                0x11, 0x22, 0x33, 0x44]))
        // deletes: empty
        Self.writeEmptyRowList(writer)

        let reader = BSATNReader(data: writer.finalize())
        let update = try TransactionUpdate(reader: reader)
        let rows = update.querySets[0].tables[0].rows[0]
        guard case .persistent(let inserts, let deletes) = rows else {
            Issue.record("Expected persistent variant")
            return
        }
        #expect(inserts.rows.count == 2)
        #expect(Array(inserts.rows[0]) == [0xAA, 0xBB, 0xCC, 0xDD])
        #expect(Array(inserts.rows[1]) == [0x11, 0x22, 0x33, 0x44])
        #expect(deletes.rows.isEmpty)
    }

    @Test func decodesMultipleQuerySetsAndTables() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(2))         // 2 query sets

        // Query set 1
        writer.write(UInt32(1))
        writer.write(UInt32(2))         // 2 tables
        try writer.write("user")
        writer.write(UInt32(1)); writer.write(UInt8(0))
        Self.writeEmptyRowList(writer); Self.writeEmptyRowList(writer)
        try writer.write("message")
        writer.write(UInt32(1)); writer.write(UInt8(0))
        Self.writeEmptyRowList(writer); Self.writeEmptyRowList(writer)

        // Query set 2
        writer.write(UInt32(2))
        writer.write(UInt32(1))
        try writer.write("audit_event")
        writer.write(UInt32(1)); writer.write(UInt8(1))
        Self.writeEmptyRowList(writer)

        let reader = BSATNReader(data: writer.finalize())
        let update = try TransactionUpdate(reader: reader)
        #expect(update.querySets.count == 2)
        #expect(update.querySets[0].querySetId.id == 1)
        #expect(update.querySets[0].tables.map(\.tableName) == ["user", "message"])
        #expect(update.querySets[1].tables[0].tableName == "audit_event")
    }
}
