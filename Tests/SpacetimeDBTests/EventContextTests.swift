import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("EventContext + variadic subscribe")
struct EventContextTests {

    struct FakeDb: Sendable {
        let label: String
    }

    struct FakeReducers: Sendable {
        let count: Int
    }

    @Test func eventContextCarriesEachField() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let db = FakeDb(label: "test-db")
        let reducers = FakeReducers(count: 3)
        let ctx = EventContext(client: client, db: db, reducers: reducers)

        #expect(ctx.db.label == "test-db")
        #expect(ctx.reducers.count == 3)
        #expect(await ctx.client.dbName == "test")
    }

    @Test func clientContextCarriesClient() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let ctx = ClientContext(client: client)
        #expect(await ctx.client.dbName == "test")
    }

    // MARK: Variadic subscribe overload

    struct FakeRow: BSATNRow, Equatable {
        static let tableName = "fake"
        let value: UInt32
        init(value: UInt32) { self.value = value }
        init(reader: BSATNReader) throws {
            self.value = try reader.read()
        }
    }

    @Test func variadicSubscribeRendersToSqlList() {
        let q1 = FakeRow.query()
        let q2 = FakeRow.query().filter { $0.col("value", UInt32.self).eq(7) }
        let queries: [any SpacetimeQuery] = [q1, q2]
        let sql = queries.map { $0.toSQL() }
        #expect(sql.contains(#"SELECT * FROM "fake""#))
        #expect(sql.contains(#"SELECT * FROM "fake" WHERE "fake"."value" = 7"#))
    }
}
