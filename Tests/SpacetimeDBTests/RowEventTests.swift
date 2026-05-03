import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("RowEvent + PK matching Tests")
struct RowEventTests {

    struct PKRow: BSATNTableWithPrimaryKey, Equatable {
        static let tableName = "pkrow"
        let id: UInt32
        let payload: String

        var primaryKey: UInt32 { id }

        init(id: UInt32, payload: String) {
            self.id = id
            self.payload = payload
        }

        init(reader: BSATNReader) throws {
            self.id = try reader.read()
            self.payload = try reader.readString()
        }
    }

    struct NoPKRow: BSATNRow, Equatable {
        static let tableName = "nopk"
        let value: UInt32

        init(value: UInt32) { self.value = value }

        init(reader: BSATNReader) throws {
            self.value = try reader.read()
        }
    }

    // MARK: matchByPrimaryKey unit tests

    @Test func matchedDeleteAndInsertCollapseToUpdate() {
        let extractor: @Sendable (Any) -> AnyHashable? = { value in
            (value as? PKRow).map { AnyHashable($0.id) }
        }
        let oldRow = PKRow(id: 1, payload: "alice")
        let newRow = PKRow(id: 1, payload: "alice2")

        let events = SpacetimeDBClient.matchByPrimaryKey(
            deletes: [oldRow],
            inserts: [newRow],
            extractor: extractor
        )

        #expect(events.count == 1)
        if case let .updated(old, new) = events[0] {
            #expect((old as? PKRow) == oldRow)
            #expect((new as? PKRow) == newRow)
        } else {
            Issue.record("Expected .updated, got \(events[0])")
        }
    }

    @Test func unmatchedDeletesAndInsertsRemainSeparate() {
        let extractor: @Sendable (Any) -> AnyHashable? = { value in
            (value as? PKRow).map { AnyHashable($0.id) }
        }
        let deleted = PKRow(id: 1, payload: "old")
        let inserted = PKRow(id: 99, payload: "new")

        let events = SpacetimeDBClient.matchByPrimaryKey(
            deletes: [deleted],
            inserts: [inserted],
            extractor: extractor
        )

        #expect(events.count == 2)
        #expect(events.contains { if case .deleted = $0 { return true }; return false })
        #expect(events.contains { if case .inserted = $0 { return true }; return false })
    }

    @Test func multipleMatchesAndLeftovers() {
        let extractor: @Sendable (Any) -> AnyHashable? = { value in
            (value as? PKRow).map { AnyHashable($0.id) }
        }
        let dels = [PKRow(id: 1, payload: "a"), PKRow(id: 2, payload: "b"), PKRow(id: 3, payload: "c")]
        let ins  = [PKRow(id: 1, payload: "A"), PKRow(id: 2, payload: "B"), PKRow(id: 4, payload: "D")]

        let events = SpacetimeDBClient.matchByPrimaryKey(deletes: dels, inserts: ins, extractor: extractor)
        #expect(events.count == 4)
        let updateCount = events.filter { if case .updated = $0 { return true }; return false }.count
        let deleteCount = events.filter { if case .deleted = $0 { return true }; return false }.count
        let insertCount = events.filter { if case .inserted = $0 { return true }; return false }.count
        #expect(updateCount == 2)   // ids 1, 2
        #expect(deleteCount == 1)   // id 3
        #expect(insertCount == 1)   // id 4
    }

    // MARK: end-to-end via TableEvent → RowEvent fan-out

    @Test func pkRowDecoderProvidesExtractor() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(PKRow.self)
        let decoder = await client.decoder(forTable: "pkrow")
        #expect(decoder?.primaryKeyExtractor != nil)
    }

    @Test func plainBSATNRowDecoderHasNoExtractor() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(NoPKRow.self)
        let decoder = await client.decoder(forTable: "nopk")
        #expect(decoder?.primaryKeyExtractor == nil)
    }

    @Test func rowEventStreamReceivesMatchedUpdate() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(PKRow.self)
        let stream = await client.rowEvents(table: "pkrow")

        let oldRow = PKRow(id: 7, payload: "old")
        let newRow = PKRow(id: 7, payload: "new")
        await client.emit(tableEvent: TableEvent(tableName: "pkrow", deletes: [oldRow], inserts: [newRow]))

        var iter = stream.makeAsyncIterator()
        let event = try #require(await iter.next())
        if case let .updated(old, new) = event {
            #expect((old as? PKRow)?.payload == "old")
            #expect((new as? PKRow)?.payload == "new")
        } else {
            Issue.record("Expected .updated, got \(event)")
        }
    }

    @Test func rowEventStreamWithoutPKEmitsDeleteAndInsert() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(NoPKRow.self)
        let stream = await client.rowEvents(table: "nopk")

        await client.emit(tableEvent: TableEvent(
            tableName: "nopk",
            deletes: [NoPKRow(value: 1)],
            inserts: [NoPKRow(value: 2)]
        ))

        var iter = stream.makeAsyncIterator()
        let first = try #require(await iter.next())
        let second = try #require(await iter.next())

        // Order: deletes then inserts (no PK to match against).
        if case .deleted(let v) = first {
            #expect((v as? NoPKRow)?.value == 1)
        } else { Issue.record("Expected .deleted first") }
        if case .inserted(let v) = second {
            #expect((v as? NoPKRow)?.value == 2)
        } else { Issue.record("Expected .inserted second") }
    }

    /// TableEvent stream still gets the FULL deletes + inserts arrays
    /// (not matched-only) — PK matching only affects rowEvents.
    @Test func tableEventStreamUnchangedByPKMatching() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(PKRow.self)
        let stream = await client.tableEvents(named: "pkrow")

        await client.emit(tableEvent: TableEvent(
            tableName: "pkrow",
            deletes: [PKRow(id: 1, payload: "old")],
            inserts: [PKRow(id: 1, payload: "new")]
        ))

        var iter = stream.makeAsyncIterator()
        let event = try #require(await iter.next())
        #expect(event.deletes.count == 1)
        #expect(event.inserts.count == 1)
    }
}
