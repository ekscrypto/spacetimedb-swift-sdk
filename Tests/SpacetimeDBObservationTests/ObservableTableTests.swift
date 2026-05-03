import Testing
import Foundation
@testable import SpacetimeDB
@testable import SpacetimeDBObservation
@testable import BSATN

@Suite("ObservableTable Tests")
struct ObservableTableTests {

    struct TestRow: BSATNTableWithPrimaryKey, Equatable {
        static let tableName = "obs_test"
        let id: UInt32
        let name: String

        var primaryKey: UInt32 { id }

        init(id: UInt32, name: String) { self.id = id; self.name = name }

        init(reader: BSATNReader) throws {
            self.id = try reader.read()
            self.name = try reader.readString()
        }
    }

    // ObservableTable requires Observation (macOS 14 / iOS 17). The
    // @Test macro disallows @available on its functions, so each test
    // gates at runtime via #available and delegates to an @available
    // helper.
    //
    // The post-emit sleeps below are to give the consumer Task a chance
    // to *process* the emitted events into `rows`. Init no longer races
    // (it awaits client.rowEvents synchronously), so emits cannot be
    // dropped — but the consumer Task still needs CPU time to apply.

    @Test func insertEventsPopulateRows() async throws {
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }
        try await runInsertEventsPopulateRows()
    }
    @available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
    private func runInsertEventsPopulateRows() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(TestRow.self)
        let table = await ObservableTable<TestRow>(client: client)

        await client.emit(tableEvent: TableEvent(
            tableName: "obs_test",
            deletes: [],
            inserts: [TestRow(id: 1, name: "alice"), TestRow(id: 2, name: "bob")]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        let snapshot = await table.rows
        #expect(snapshot[1] == TestRow(id: 1, name: "alice"))
        #expect(snapshot[2] == TestRow(id: 2, name: "bob"))
        #expect(snapshot.count == 2)
    }

    @Test func updatedEventReplacesRow() async throws {
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }
        try await runUpdatedEventReplacesRow()
    }
    @available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
    private func runUpdatedEventReplacesRow() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(TestRow.self)
        let table = await ObservableTable<TestRow>(client: client)

        await client.emit(tableEvent: TableEvent(
            tableName: "obs_test",
            deletes: [],
            inserts: [TestRow(id: 7, name: "old")]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        // PK-matched delete + insert → folded into .updated by the SDK.
        await client.emit(tableEvent: TableEvent(
            tableName: "obs_test",
            deletes: [TestRow(id: 7, name: "old")],
            inserts: [TestRow(id: 7, name: "new")]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        let row = await table.rows[7]
        #expect(row == TestRow(id: 7, name: "new"))
        let count = await table.count
        #expect(count == 1)
    }

    @Test func deleteEventRemovesRow() async throws {
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }
        try await runDeleteEventRemovesRow()
    }
    @available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
    private func runDeleteEventRemovesRow() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(TestRow.self)
        let table = await ObservableTable<TestRow>(client: client)

        await client.emit(tableEvent: TableEvent(
            tableName: "obs_test",
            deletes: [],
            inserts: [TestRow(id: 1, name: "a"), TestRow(id: 2, name: "b")]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        await client.emit(tableEvent: TableEvent(
            tableName: "obs_test",
            deletes: [TestRow(id: 1, name: "a")],
            inserts: []
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        let snapshot = await table.rows
        #expect(snapshot[1] == nil)
        #expect(snapshot[2] == TestRow(id: 2, name: "b"))
    }

    @Test func subscriptAndValuesAccessors() async throws {
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }
        try await runSubscriptAndValuesAccessors()
    }
    @available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
    private func runSubscriptAndValuesAccessors() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(TestRow.self)
        let table = await ObservableTable<TestRow>(client: client)

        await client.emit(tableEvent: TableEvent(
            tableName: "obs_test",
            deletes: [],
            inserts: [TestRow(id: 42, name: "answer")]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        let viaSubscript = await table[42]
        #expect(viaSubscript?.name == "answer")
        let allValues = await Array(table.values)
        #expect(allValues.count == 1)
    }
}
