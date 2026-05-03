import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("Table<Row> typed view")
struct TableTests {

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

    // MARK: PK table cache

    @Test func cacheReflectsInsertsAndDeletesByPrimaryKey() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(PKRow.self)
        let table = await Table<PKRow>(client: client)

        await client.emit(tableEvent: TableEvent(
            tableName: PKRow.tableName,
            deletes: [],
            inserts: [PKRow(id: 1, payload: "a"), PKRow(id: 2, payload: "b")]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        let countAfterInsert = await table.count
        #expect(countAfterInsert == 2)
        let aliceLookup = await table.find(1)
        #expect(aliceLookup?.payload == "a")

        await client.emit(tableEvent: TableEvent(
            tableName: PKRow.tableName,
            deletes: [PKRow(id: 1, payload: "a")],
            inserts: []
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        let countAfterDelete = await table.count
        #expect(countAfterDelete == 1)
        let aliceGone = await table.find(1)
        #expect(aliceGone == nil)
        let bobStill = await table.find(2)
        #expect(bobStill?.payload == "b")
    }

    @Test func updatedEventReplacesCachedRow() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(PKRow.self)
        let table = await Table<PKRow>(client: client)

        await client.emit(tableEvent: TableEvent(
            tableName: PKRow.tableName,
            deletes: [],
            inserts: [PKRow(id: 7, payload: "old")]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        // PK-matched delete + insert collapses to .updated via the receive
        // loop's matchByPrimaryKey path.
        await client.emit(tableEvent: TableEvent(
            tableName: PKRow.tableName,
            deletes: [PKRow(id: 7, payload: "old")],
            inserts: [PKRow(id: 7, payload: "new")]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        let row = await table.find(7)
        #expect(row?.payload == "new")
        let count = await table.count
        #expect(count == 1)
    }

    // MARK: Callbacks

    @Test func onInsertAndOnDeleteCallbacksFire() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(PKRow.self)
        let table = await Table<PKRow>(client: client)

        let inserted = AtomicBox<[UInt32]>([])
        let deleted = AtomicBox<[UInt32]>([])

        await table.onInsert { row in inserted.append(row.id) }
        await table.onDelete { row in deleted.append(row.id) }

        await client.emit(tableEvent: TableEvent(
            tableName: PKRow.tableName,
            deletes: [],
            inserts: [PKRow(id: 10, payload: "x"), PKRow(id: 11, payload: "y")]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(Set(inserted.snapshot()) == [10, 11])

        await client.emit(tableEvent: TableEvent(
            tableName: PKRow.tableName,
            deletes: [PKRow(id: 10, payload: "x")],
            inserts: []
        ))
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(deleted.snapshot() == [10])
    }

    @Test func onUpdateCallbackOnlyAvailableForPKTables() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(PKRow.self)
        let table = await Table<PKRow>(client: client)

        let updates = AtomicBox<[(UInt32, String, String)]>([])
        await table.onUpdate { old, new in
            updates.append((new.id, old.payload, new.payload))
        }

        await client.emit(tableEvent: TableEvent(
            tableName: PKRow.tableName,
            deletes: [PKRow(id: 5, payload: "before")],
            inserts: [PKRow(id: 5, payload: "after")]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        let snapshot = updates.snapshot()
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.0 == 5)
        #expect(snapshot.first?.1 == "before")
        #expect(snapshot.first?.2 == "after")
    }

    @Test func removingCallbackStopsFiring() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(PKRow.self)
        let table = await Table<PKRow>(client: client)

        let counter = AtomicBox<[UInt32]>([])
        let token = await table.onInsert { row in counter.append(row.id) }

        await client.emit(tableEvent: TableEvent(
            tableName: PKRow.tableName,
            deletes: [],
            inserts: [PKRow(id: 1, payload: "first")]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(counter.snapshot().count == 1)

        await table.removeOnInsert(token)

        await client.emit(tableEvent: TableEvent(
            tableName: PKRow.tableName,
            deletes: [],
            inserts: [PKRow(id: 2, payload: "second")]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(counter.snapshot().count == 1)
    }

    // MARK: Non-PK tables

    @Test func nonPKTableCachesByEqualityAndAllowsBasicAccess() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(NoPKRow.self)
        let table = await Table<NoPKRow>(client: client)

        await client.emit(tableEvent: TableEvent(
            tableName: NoPKRow.tableName,
            deletes: [],
            inserts: [NoPKRow(value: 100), NoPKRow(value: 200)]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        let count = await table.count
        #expect(count == 2)
        let snapshot = await table.iter()
        #expect(Set(snapshot.map { $0.value }) == [100, 200])
    }

    @Test func filterReturnsMatchingRows() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(PKRow.self)
        let table = await Table<PKRow>(client: client)

        await client.emit(tableEvent: TableEvent(
            tableName: PKRow.tableName,
            deletes: [],
            inserts: [
                PKRow(id: 1, payload: "alpha"),
                PKRow(id: 2, payload: "beta"),
                PKRow(id: 3, payload: "alpha")
            ]
        ))
        try await Task.sleep(nanoseconds: 50_000_000)

        let alphas = await table.filter { $0.payload == "alpha" }
        #expect(Set(alphas.map { $0.id }) == [1, 3])
    }
}

/// Tiny thread-safe collector used so the @Sendable callback closures
/// can record calls without capturing a mutable variable.
final class AtomicBox<Value: Sendable>: @unchecked Sendable {
    private var lock = NSLock()
    private var value: Value

    init(_ initial: Value) { self.value = initial }

    func snapshot() -> Value {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

extension AtomicBox where Value == [UInt32] {
    func append(_ element: UInt32) {
        lock.lock(); defer { lock.unlock() }
        value.append(element)
    }
}

extension AtomicBox where Value == [(UInt32, String, String)] {
    func append(_ element: (UInt32, String, String)) {
        lock.lock(); defer { lock.unlock() }
        value.append(element)
    }
}
