import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("Phase 9 polish Tests")
struct Phase9Tests {

    // MARK: Gzip decompression

    /// Round-trip test: gzip a known QueryUpdate-shaped payload via
    /// /usr/bin/gzip, then ensure the SDK's gzip decoder produces the
    /// original bytes back.
    @Test func gzipRoundTrip() throws {
        // Synthesize a deterministic payload to compress.
        let payload = "Hello, SpacetimeDB! ".data(using: .utf8)!
            + Data((0..<256).map { UInt8($0 & 0xff) })
            + "Trailer.".data(using: .utf8)!

        let gzipped = try gzipUsingShell(payload)
        let decompressed = try MessageDecompression.gzip(gzipped)
        #expect(decompressed == payload)
    }

    @Test func gzipRejectsBadMagic() {
        let bogus = Data(repeating: 0xff, count: 64)
        #expect(throws: BSATNError.self) {
            _ = try MessageDecompression.gzip(bogus)
        }
    }

    @Test func gzipRejectsTooShort() {
        #expect(throws: BSATNError.self) {
            _ = try MessageDecompression.gzip(Data(repeating: 0, count: 4))
        }
    }

    /// Strip-framing parses the header correctly even with FNAME set
    /// (filename embedded in the gzip stream).
    @Test func gzipStripsFNameHeader() throws {
        let payload = "abc".data(using: .utf8)!
        let gzipped = try gzipUsingShell(payload, withFilename: true)
        let decompressed = try MessageDecompression.gzip(gzipped)
        #expect(decompressed == payload)
    }

    // MARK: withConfirmedReads option

    @Test func confirmedReadsDefaultsFalse() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let value = await client.confirmedReads
        #expect(value == false)
    }

    @Test func confirmedReadsCanBeEnabled() async throws {
        let client = try SpacetimeDBClient(
            host: "http://localhost:3000",
            db: "test",
            confirmedReads: true
        )
        let value = await client.confirmedReads
        #expect(value == true)
    }

    // MARK: Credentials

    @Test func credentialsFileRoundTrip() throws {
        let id = try #require(Identity(hex: String(repeating: "a", count: 64)))
        let creds = Credentials(token: "tok-1234", identity: id)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("creds-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try creds.save(to: url)
        let loaded = try #require(try Credentials.load(from: url))

        #expect(loaded.token == "tok-1234")
        #expect(loaded.identity == id)
    }

    @Test func credentialsLoadFromMissingFileReturnsNil() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        let loaded = try Credentials.load(from: url)
        #expect(loaded == nil)
    }

    @Test func credentialsAuthenticationTokenAccessor() throws {
        let id = try #require(Identity(hex: String(repeating: "0", count: 64)))
        let creds = Credentials(token: "abc", identity: id)
        #expect(creds.authenticationToken.rawValue == "abc")
    }

    #if canImport(Security)
    @Test func credentialsKeychainRoundTrip() throws {
        // Use a unique service name per run to avoid colliding with
        // anything else in the developer's keychain.
        let service = "spacetimedb.test.\(UUID().uuidString)"
        let id = try #require(Identity(hex: String(repeating: "f", count: 64)))
        let creds = Credentials(token: "kc-token", identity: id)

        defer { try? Credentials.delete(service: service) }

        try creds.save(service: service)
        let loaded = try #require(try Credentials.load(service: service))
        #expect(loaded.token == "kc-token")
        #expect(loaded.identity == id)

        try Credentials.delete(service: service)
        let afterDelete = try Credentials.load(service: service)
        #expect(afterDelete == nil)
    }
    #endif

    // MARK: subscribeToAllTables

    struct TableA: BSATNRow, Equatable {
        static let tableName = "alpha"
        let n: UInt32
        init(n: UInt32) { self.n = n }
        init(reader: BSATNReader) throws { self.n = try reader.read() }
    }

    struct TableB: BSATNRow, Equatable {
        static let tableName = "beta"
        let s: String
        init(s: String) { self.s = s }
        init(reader: BSATNReader) throws { self.s = try reader.readString() }
    }

    @Test func registeredTableNamesReturnsRegisteredOnly() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(TableA.self)
        await client.registerTableRowDecoder(TableB.self)
        let names = await Set(client.registeredTableNames())
        #expect(names == ["alpha", "beta"])
    }

    @Test func subscribeToAllTablesThrowsWhenNoneRegistered() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await #expect(throws: SpacetimeDBError.self) {
            _ = try await client.subscribeToAllTables()
        }
    }

    // MARK: Helpers

    /// Use /usr/bin/gzip to produce a real RFC 1952 stream so we know
    /// the decoder is interoperating with a canonical implementation.
    private func gzipUsingShell(_ payload: Data, withFilename: Bool = false) throws -> Data {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gzip-input-\(UUID().uuidString)\(withFilename ? ".bin" : "")")
        try payload.write(to: tmp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tmp) }
        defer { try? FileManager.default.removeItem(at: tmp.appendingPathExtension("gz")) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        proc.arguments = withFilename ? ["-f", "-N", tmp.path] : ["-n", "-f", tmp.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "gzip", code: Int(proc.terminationStatus))
        }
        return try Data(contentsOf: tmp.appendingPathExtension("gz"))
    }
}
