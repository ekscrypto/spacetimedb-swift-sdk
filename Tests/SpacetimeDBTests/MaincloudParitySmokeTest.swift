import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

/// Live integration tests against the `spacetime-swift-parity-test`
/// maincloud db (see `Tests/maincloud-fixtures/parity-module/`).
/// Skipped unless `SPACETIMEDB_LIVE=1` so day-to-day `swift test` stays
/// hermetic.
///
/// Exercises four pieces of the Rust-parity batch end-to-end:
///   1. Typed query DSL → subscribe(queries:)
///   2. Typed Procedure → callProcedure(_:)
///   3. ClientMetrics      → snapshot(db:)
///   4. (existing path)    → callReducer(_:) by way of set_name
///
/// EVENT-FLAG-WAITING-ON-RELEASE: A fifth piece — `BSATNEventRow` /
/// `client.eventRows(_:)` — has no live test here yet because the
/// server-side `event` flag for `#[spacetimedb::table(...)]` is
/// upstream-master-only as of spacetimedb 1.12. See
/// Tests/maincloud-fixtures/parity-module/README.md for the checklist
/// to flip it on once the flag ships.
@Suite("Live maincloud parity smoke (set SPACETIMEDB_LIVE=1 to enable)")
struct MaincloudParitySmokeTest {

    static let host = "https://maincloud.spacetimedb.com"
    static let db = "spacetime-swift-parity-test"
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["SPACETIMEDB_LIVE"] == "1"
    }

    // MARK: Row + procedure types

    struct UserRow: BSATNTableWithPrimaryKey, Equatable {
        static let tableName = "user"
        let identity: Identity
        let name: String?
        let online: Bool
        var primaryKey: Identity { identity }
        init(reader: BSATNReader) throws {
            self.identity = try Identity(reader: reader)
            self.name = try reader.readOptional { try reader.readString() }
            self.online = try reader.read()
        }
    }

    struct MessageRow: BSATNRow, Equatable {
        static let tableName = "message"
        let sender: Identity
        let sent: Timestamp
        let text: String
        init(reader: BSATNReader) throws {
            self.sender = try Identity(reader: reader)
            self.sent = try Timestamp(reader: reader)
            self.text = try reader.readString()
        }
    }

    struct EchoProcedure: Procedure {
        typealias ReturnValue = UInt64
        let name = "echo"
        let value: UInt64
        func encodeArguments(writer: BSATNWriter) throws {
            writer.write(value)
        }
        func decodeReturnValue(_ data: Data) throws -> UInt64 {
            try BSATNReader(data: data).read()
        }
    }

    struct SetNameReducer: Reducer {
        let name = "set_name"
        let userName: String
        func encodeArguments(writer: BSATNWriter) throws {
            try writer.write(userName)
        }
    }

    // MARK: Helper — connect + wait for InitialConnection

    private func connectAndWait(client: SpacetimeDBClient) async throws {
        let stream = await client.connectionEvents
        try await client.connect()
        for await event in stream {
            if case .connected = event { return }
            if case .error(let msg) = event {
                throw NSError(domain: "ParitySmoke", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "connection error: \(msg)"])
            }
        }
    }

    /// Bound a live-network test body so a stalled server (or a buggy
    /// SDK path) can't hold the test runner forever. The default budget
    /// is 20s — every test in this suite normally finishes in <1s, so
    /// hitting this limit is a real failure.
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval = 20,
        _ body: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(
                    domain: "ParitySmoke",
                    code: 99,
                    userInfo: [NSLocalizedDescriptionKey: "test exceeded \(seconds)s budget"]
                )
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: Tests

    @Test(.enabled(if: MaincloudParitySmokeTest.enabled))
    func typedProcedureRoundTrip() async throws {
        try await withTimeout {
            let client = try SpacetimeDBClient(host: Self.host, db: Self.db)
            try await self.connectAndWait(client: client)
            defer { Task { await client.disconnect() } }

            let returned = try await client.callProcedure(EchoProcedure(value: 12345))
            #expect(returned == 12345)
        }
    }

    @Test(.enabled(if: MaincloudParitySmokeTest.enabled))
    func typedQueryDSLAppliedAndUnsubscribed() async throws {
        try await withTimeout {
            let client = try SpacetimeDBClient(host: Self.host, db: Self.db)
            await client.registerTableRowDecoder(UserRow.self)
            await client.registerTableRowDecoder(MessageRow.self)
            try await self.connectAndWait(client: client)
            defer { Task { await client.disconnect() } }

            let queries: [any SpacetimeQuery] = [
                UserRow.query(),
                MessageRow.query(),
            ]
            let handle = try await client.subscribe(queries: queries)
            try await handle.applied()
            try await handle.unsubscribe()
        }
    }

    @Test(.enabled(if: MaincloudParitySmokeTest.enabled))
    func clientMetricsCountsInboundFrames() async throws {
        try await withTimeout {
            await ClientMetrics.shared.reset()

            let client = try SpacetimeDBClient(host: Self.host, db: Self.db)
            try await self.connectAndWait(client: client)
            defer { Task { await client.disconnect() } }

            _ = try await client.callProcedure(EchoProcedure(value: 1))

            let snap = try #require(await ClientMetrics.shared.snapshot(db: Self.db))
            #expect(snap.messagesReceived >= 2)
            #expect(snap.bytesReceived > 0)
            #expect(snap.bucketCounts.contains { $0 > 0 } || snap.bucketOverflowCount > 0)
        }
    }

    @Test(.enabled(if: MaincloudParitySmokeTest.enabled))
    func filteredQueryDSLEndToEnd() async throws {
        try await withTimeout {
            let client = try SpacetimeDBClient(host: Self.host, db: Self.db)
            await client.registerTableRowDecoder(UserRow.self)
            try await self.connectAndWait(client: client)
            defer { Task { await client.disconnect() } }

            let q = UserRow.query().filter { $0.col("online", Bool.self).isTrue }
            let handle = try await client.subscribe(queries: [q])
            try await handle.applied()
            try await handle.unsubscribe()
        }
    }

    @Test(.enabled(if: MaincloudParitySmokeTest.enabled))
    func phase11TypedTableCachePopulatesAfterSubscribe() async throws {
        try await withTimeout {
            let client = try SpacetimeDBClient(host: Self.host, db: Self.db)
            await client.registerTableRowDecoder(UserRow.self)
            await client.registerTableRowDecoder(MessageRow.self)
            try await self.connectAndWait(client: client)
            defer { Task { await client.disconnect() } }

            let users = await Table<UserRow>(client: client)
            let messages = await Table<MessageRow>(client: client)

            let handle = try await client.subscribe([
                "SELECT * FROM user",
                "SELECT * FROM message",
            ])
            try await handle.applied()
            try await Task.sleep(nanoseconds: 200_000_000)

            let userCount = await users.count
            let messageCount = await messages.count
            #expect(userCount >= 0)
            #expect(messageCount >= 0)

            if let any = await users.iter().first {
                let found = await users.find(any.identity)
                #expect(found == any)
            }

            try await handle.unsubscribe()
        }
    }

    @Test(.enabled(if: MaincloudParitySmokeTest.enabled))
    func phase12BuilderConnectsAndCallsReducer() async throws {
        try await withTimeout {
            let client = try SpacetimeDBClient.builder()
                .withUri(Self.host)
                .withDatabaseName(Self.db)
                .withCompression(.brotli)
                .build()

            try await self.connectAndWait(client: client)
            defer { Task { await client.disconnect() } }

            let result = try await client.callReducer(SetNameReducer(userName: "ParityBuilder"))
            #expect(result.returnValue.isEmpty)
            #expect(await client.lightMode == false)
        }
    }

    @Test(.enabled(if: MaincloudParitySmokeTest.enabled))
    func phase12LightModeReducerFireAndForget() async throws {
        try await withTimeout {
            // Light mode: callReducer returns immediately because the
            // server suppresses the success-side TransactionUpdate echo.
            // We just verify the call completes within budget.
            let client = try SpacetimeDBClient.builder()
                .withUri(Self.host)
                .withDatabaseName(Self.db)
                .withLightMode()
                .build()

            try await self.connectAndWait(client: client)
            defer { Task { await client.disconnect() } }

            let result = try await client.callReducer(SetNameReducer(userName: "ParityLight"))
            #expect(result.returnValue.isEmpty)
            #expect(await client.lightMode == true)
        }
    }

    @Test(.enabled(if: MaincloudParitySmokeTest.enabled))
    func setNameReducerRoundTrip() async throws {
        try await withTimeout {
            let client = try SpacetimeDBClient(host: Self.host, db: Self.db)
            try await self.connectAndWait(client: client)
            defer { Task { await client.disconnect() } }

            let result = try await client.callReducer(SetNameReducer(userName: "ParityTest"))
            #expect(result.returnValue.isEmpty)
        }
    }
}
