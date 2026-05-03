import Testing
import Foundation
@testable import spacetime_swift

@Suite("spacetime-swift codegen end-to-end Tests")
struct CodegenEndToEndTests {

    static let fixtureURL: URL = {
        Bundle.module.url(forResource: "quickstart-chat-55kji", withExtension: "json")!
    }()

    static func loadSchema() throws -> SchemaDoc {
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(SchemaDoc.self, from: data)
    }

    @Test func parsesMaincloudFixture() throws {
        let doc = try Self.loadSchema()
        #expect(doc.database == "quickstart-chat-55kji")
        #expect(doc.tables.count == 2)
        #expect(doc.tables.contains(where: { $0.name == "user" && $0.primaryKey == [0] }))
        #expect(doc.tables.contains(where: { $0.name == "message" && $0.primaryKey.isEmpty }))
        #expect(doc.reducers.count == 4)
    }

    @Test func emitsExpectedFiles() throws {
        let doc = try Self.loadSchema()
        let emitter = SwiftEmitter(schema: doc)
        let files = emitter.emit()
        #expect(Set(files.keys) == [
            "UserRow.swift",
            "MessageRow.swift",
            "SendMessageReducer.swift",
            "SetNameReducer.swift",
            "Db.swift",
        ])
    }

    @Test func userRowIsTableWithPrimaryKey() throws {
        let doc = try Self.loadSchema()
        let src = SwiftEmitter(schema: doc).emit()["UserRow.swift"] ?? ""
        #expect(src.contains("public struct UserRow: BSATNTableWithPrimaryKey"))
        #expect(src.contains("public let identity: Identity"))
        #expect(src.contains("public let name: String?"))
        #expect(src.contains("public let online: Bool"))
        #expect(src.contains("public var primaryKey: Identity { identity }"))
        #expect(src.contains("self.identity = try Identity(reader: reader)"))
        #expect(src.contains("self.name = try reader.readOptional { try reader.readString() }"))
    }

    @Test func messageRowIsPlainBSATNRow() throws {
        let doc = try Self.loadSchema()
        let src = SwiftEmitter(schema: doc).emit()["MessageRow.swift"] ?? ""
        #expect(src.contains("public struct MessageRow: BSATNRow"))
        #expect(!src.contains("BSATNTableWithPrimaryKey"))
        #expect(src.contains("public let sender: Identity"))
        #expect(src.contains("public let sent: Timestamp"))
        #expect(src.contains("self.sent = try Timestamp(reader: reader)"))
    }

    @Test func reducerEmissionRenamesNameCollision() throws {
        let doc = try Self.loadSchema()
        let src = SwiftEmitter(schema: doc).emit()["SetNameReducer.swift"] ?? ""
        #expect(src.contains("public let name = \"set_name\""))
        #expect(src.contains("public let nameArg: String"))
        #expect(src.contains("public init(nameArg: String)"))
        #expect(src.contains("try writer.write(nameArg)"))
    }

    @Test func sendMessageReducerEmitsAsExpected() throws {
        let doc = try Self.loadSchema()
        let src = SwiftEmitter(schema: doc).emit()["SendMessageReducer.swift"] ?? ""
        #expect(src.contains("public let name = \"send_message\""))
        #expect(src.contains("public let text: String"))
        #expect(src.contains("try writer.write(text)"))
    }

    @Test func lifecycleReducersAreSkipped() throws {
        let doc = try Self.loadSchema()
        let files = SwiftEmitter(schema: doc).emit()
        #expect(files["ClientConnectedReducer.swift"] == nil)
        #expect(files["IdentityDisconnectedReducer.swift"] == nil)
    }

    @Test func generatedCodeTypeChecksAgainstSDK() throws {
        let doc = try Self.loadSchema()
        try typecheck(files: SwiftEmitter(schema: doc).emit())
    }

    // MARK: Phase 8b — richer fixture (arrays, named refs, named sums)

    @Test func richFixtureEmitsAccountRoleAndAddress() throws {
        let url = Bundle.module.url(forResource: "synthetic-rich", withExtension: "json")!
        let doc = try JSONDecoder().decode(SchemaDoc.self, from: Data(contentsOf: url))
        let files = SwiftEmitter(schema: doc).emit()

        #expect(Set(files.keys) == [
            "AccountRow.swift",
            "Address.swift",
            "UserRole.swift",
            "AddTagsReducer.swift",
            "SetRoleReducer.swift",
            "Db.swift",
        ])
    }

    @Test func richFixtureNamedRefResolvesToType() throws {
        let url = Bundle.module.url(forResource: "synthetic-rich", withExtension: "json")!
        let doc = try JSONDecoder().decode(SchemaDoc.self, from: Data(contentsOf: url))
        let acct = SwiftEmitter(schema: doc).emit()["AccountRow.swift"] ?? ""
        #expect(acct.contains("public let role: UserRole"))
        #expect(acct.contains("public let home: Address"))
        #expect(acct.contains("self.role = try UserRole(reader: reader)"))
        #expect(acct.contains("self.home = try Address(reader: reader)"))
    }

    @Test func richFixtureArrayUsesTypedReader() throws {
        let url = Bundle.module.url(forResource: "synthetic-rich", withExtension: "json")!
        let doc = try JSONDecoder().decode(SchemaDoc.self, from: Data(contentsOf: url))
        let acct = SwiftEmitter(schema: doc).emit()["AccountRow.swift"] ?? ""
        #expect(acct.contains("public let tags: [String]"))
        #expect(acct.contains("self.tags = try reader.readTypedArray { try reader.readString() }"))
    }

    @Test func richFixtureSumTypeEmitsEnumWithVariants() throws {
        let url = Bundle.module.url(forResource: "synthetic-rich", withExtension: "json")!
        let doc = try JSONDecoder().decode(SchemaDoc.self, from: Data(contentsOf: url))
        let role = SwiftEmitter(schema: doc).emit()["UserRole.swift"] ?? ""
        #expect(role.contains("public enum UserRole: Equatable, Sendable"))
        #expect(role.contains("case admin\n"))
        #expect(role.contains("case member(String)"))
        #expect(role.contains("case banned(UInt64)"))
        #expect(role.contains("case 0: self = .admin"))
        #expect(role.contains("case 1: self = .member(try reader.readString())"))
        #expect(role.contains("case 2: self = .banned(try reader.read())"))
        #expect(role.contains("throw BSATNError.invalidSumTag(tag)"))
    }

    @Test func richFixtureReducerEncodesArrayAndNamedType() throws {
        let url = Bundle.module.url(forResource: "synthetic-rich", withExtension: "json")!
        let doc = try JSONDecoder().decode(SchemaDoc.self, from: Data(contentsOf: url))
        let files = SwiftEmitter(schema: doc).emit()

        let addTags = files["AddTagsReducer.swift"] ?? ""
        #expect(addTags.contains("public let tags: [String]"))
        #expect(addTags.contains("try writer.writeTypedArray(tags) { try writer.write($0) }"))

        let setRole = files["SetRoleReducer.swift"] ?? ""
        #expect(setRole.contains("public let role: UserRole"))
        #expect(setRole.contains("try role.write(to: writer)"))
    }

    @Test func richFixtureGeneratedCodeTypeChecks() throws {
        let url = Bundle.module.url(forResource: "synthetic-rich", withExtension: "json")!
        let doc = try JSONDecoder().decode(SchemaDoc.self, from: Data(contentsOf: url))
        try typecheck(files: SwiftEmitter(schema: doc).emit())
    }

    // MARK: Event-table fixture (Rust EventTable parity)

    private static func loadEventFixture() throws -> SchemaDoc {
        let url = Bundle.module.url(forResource: "synthetic-event", withExtension: "json")!
        return try JSONDecoder().decode(SchemaDoc.self, from: Data(contentsOf: url))
    }

    @Test func eventTableFlagDecodesFromSchema() throws {
        let doc = try Self.loadEventFixture()
        let player = doc.tables.first { $0.name == "player" }!
        let telemetry = doc.tables.first { $0.name == "telemetry_event" }!
        #expect(player.isEvent == false)
        #expect(telemetry.isEvent == true)
    }

    @Test func eventTableEmitsBSATNEventRow() throws {
        let doc = try Self.loadEventFixture()
        let src = SwiftEmitter(schema: doc).emit()["TelemetryEventRow.swift"] ?? ""
        #expect(src.contains("public struct TelemetryEventRow: BSATNEventRow"))
        #expect(!src.contains("BSATNTableWithPrimaryKey"))
        #expect(!src.contains("BSATNRow,"))
        #expect(!src.contains("primaryKey"))
    }

    @Test func nonEventTableStillEmitsPK() throws {
        let doc = try Self.loadEventFixture()
        let src = SwiftEmitter(schema: doc).emit()["PlayerRow.swift"] ?? ""
        #expect(src.contains("public struct PlayerRow: BSATNTableWithPrimaryKey"))
        #expect(src.contains("public var primaryKey: UInt64 { id }"))
    }

    @Test func eventFixtureGeneratedCodeTypeChecks() throws {
        let doc = try Self.loadEventFixture()
        try typecheck(files: SwiftEmitter(schema: doc).emit())
    }

    // MARK: Typed-query Cols emission (Rust query-builder parity)

    @Test func userRowEmitsBSATNRowQueryableCols() throws {
        let doc = try Self.loadSchema()
        let src = SwiftEmitter(schema: doc).emit()["UserRow.swift"] ?? ""
        #expect(src.contains("extension UserRow: BSATNRowQueryable"))
        #expect(src.contains("public struct Cols: Sendable"))
        // Identity column with the SQL column name preserved.
        #expect(src.contains("public let identity: QueryColumn<UserRow, Identity>"))
        // Optional name column — Optional<String> is SQL-encodable.
        #expect(src.contains("public let name: QueryColumn<UserRow, String?>"))
        #expect(src.contains("public let online: QueryColumn<UserRow, Bool>"))
        #expect(src.contains("identity: QueryColumn<UserRow, Identity>(tableAlias: tableAlias, name: \"identity\")"))
    }

    @Test func messageRowColsIncludesPrimitivesOnly() throws {
        let doc = try Self.loadSchema()
        let src = SwiftEmitter(schema: doc).emit()["MessageRow.swift"] ?? ""
        // sender (Identity), sent (Timestamp), text (String) are all
        // SQL-encodable; column emitted for each.
        #expect(src.contains("public let sender: QueryColumn<MessageRow, Identity>"))
        #expect(src.contains("public let sent: QueryColumn<MessageRow, Timestamp>"))
        #expect(src.contains("public let text: QueryColumn<MessageRow, String>"))
    }

    @Test func richFixtureColsSkipUnsupportedTypes() throws {
        let url = Bundle.module.url(forResource: "synthetic-rich", withExtension: "json")!
        let doc = try JSONDecoder().decode(SchemaDoc.self, from: Data(contentsOf: url))
        let src = SwiftEmitter(schema: doc).emit()["AccountRow.swift"] ?? ""
        // id, email primitive; tags is [String] (skipped); role / home are named refs (skipped).
        #expect(src.contains("public let id: QueryColumn<AccountRow, UInt64>"))
        #expect(src.contains("public let email: QueryColumn<AccountRow, String>"))
        #expect(!src.contains("public let tags: QueryColumn"))
        #expect(!src.contains("public let role: QueryColumn"))
        #expect(!src.contains("public let home: QueryColumn"))
    }

    // MARK: Phase 11 — typed Db accessor emission

    @Test func emitsDbWithTypedTableProperties() throws {
        let doc = try Self.loadSchema()
        let src = SwiftEmitter(schema: doc).emit()["Db.swift"] ?? ""
        #expect(src.contains("public struct Db: Sendable"))
        #expect(src.contains("public let user: Table<UserRow>"))
        #expect(src.contains("public let message: Table<MessageRow>"))
        #expect(src.contains("public static func attach(to client: SpacetimeDBClient) async -> Db"))
        #expect(src.contains("await client.registerTableRowDecoder(UserRow.self)"))
        #expect(src.contains("await client.registerTableRowDecoder(MessageRow.self)"))
        #expect(src.contains("user: Table<UserRow>(client: client)"))
        #expect(src.contains("message: Table<MessageRow>(client: client)"))
    }

    @Test func dbEmissionSkipsEventTables() throws {
        let doc = try Self.loadEventFixture()
        let src = SwiftEmitter(schema: doc).emit()["Db.swift"] ?? ""
        // PlayerRow is a normal table; TelemetryEventRow is event-only and skipped.
        #expect(src.contains("public let player: Table<PlayerRow>"))
        #expect(!src.contains("Table<TelemetryEventRow>"))
    }

    @Test func tablesWithoutIsEventFieldDefaultToFalse() throws {
        // The maincloud quickstart-chat fixture predates is_event; make
        // sure the optional decode path treats it as false.
        let doc = try Self.loadSchema()
        for table in doc.tables {
            #expect(table.isEvent == false)
        }
    }

    // MARK: Helpers

    private func typecheck(files: [String: String]) throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spacetime-swift-codegen-tc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        for (name, contents) in files {
            try contents.write(to: tmp.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let cwd = FileManager.default.currentDirectoryPath
        let candidates = [
            ".build/arm64-apple-macosx/debug/Modules",
            ".build/x86_64-apple-macosx/debug/Modules",
            ".build/debug/Modules",
        ].map { URL(fileURLWithPath: cwd).appendingPathComponent($0) }
        guard let modulesDir = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return
        }
        let buildRoot = modulesDir.deletingLastPathComponent()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "swiftc",
            "-typecheck",
            "-I", modulesDir.path,
            "-I", buildRoot.path,
            "-L", buildRoot.path,
            "-module-name", "GeneratedCheck",
        ] + files.keys.sorted().map { tmp.appendingPathComponent($0).path }
        let stderr = Pipe()
        proc.standardError = stderr
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            Issue.record("swiftc -typecheck failed: \(String(data: data, encoding: .utf8) ?? "<no output>")")
        }
    }
}
