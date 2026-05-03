import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("Phase 12: DbConnectionBuilder")
struct DbConnectionBuilderTests {

    @Test func builderCarriesEveryConfiguredOption() {
        let builder = SpacetimeDBClient.builder()
            .withUri("https://maincloud.spacetimedb.com")
            .withDatabaseName("quickstart-chat-55kji")
            .withToken(AuthenticationToken(rawValue: "abc"))
            .withCompression(.gzip)
            .withConfirmedReads()
            .withLightMode()
            .withDebug(true)
            .withAutoReconnect(false)

        let config = builder.debugConfiguration
        #expect(config.uri == "https://maincloud.spacetimedb.com")
        #expect(config.dbName == "quickstart-chat-55kji")
        #expect(config.token?.rawValue == "abc")
        #expect(config.compression == .gzip)
        #expect(config.confirmedReads == true)
        #expect(config.lightMode == true)
        #expect(config.debugEnabled == true)
        #expect(config.enableAutoReconnect == false)
    }

    @Test func builderDefaultsMatchClientDefaults() {
        let builder = SpacetimeDBClient.builder()
        let config = builder.debugConfiguration
        #expect(config.compression == .brotli)
        #expect(config.confirmedReads == false)
        #expect(config.lightMode == false)
        #expect(config.debugEnabled == false)
        #expect(config.enableAutoReconnect == true)
        #expect(config.token == nil)
    }

    @Test func builderRequiresUriAndDatabaseName() {
        do {
            _ = try SpacetimeDBClient.builder().build()
            Issue.record("Expected build() to throw .missingUri")
        } catch DbConnectionBuilder.BuilderError.missingUri {
            // ok
        } catch {
            Issue.record("Expected .missingUri, got \(error)")
        }

        do {
            _ = try SpacetimeDBClient.builder().withUri("https://x.test").build()
            Issue.record("Expected build() to throw .missingDatabaseName")
        } catch DbConnectionBuilder.BuilderError.missingDatabaseName {
            // ok
        } catch {
            Issue.record("Expected .missingDatabaseName, got \(error)")
        }
    }

    @Test func buildProducesUsableClient() async throws {
        let client = try SpacetimeDBClient.builder()
            .withUri("https://maincloud.spacetimedb.com")
            .withDatabaseName("quickstart-chat-55kji")
            .withCompression(.brotli)
            .withLightMode(true)
            .build()

        #expect(await client.host == "https://maincloud.spacetimedb.com")
        #expect(await client.dbName == "quickstart-chat-55kji")
        #expect(await client.lightMode == true)
        #expect(await client.connected == false)
    }

    @Test func builderImmutabilityAcrossWithCalls() {
        let base = SpacetimeDBClient.builder().withUri("https://a.test")
        let extended = base.withDatabaseName("db1")
        // base must not have been mutated by .withDatabaseName on the copy.
        #expect(base.debugConfiguration.dbName == nil)
        #expect(extended.debugConfiguration.dbName == "db1")
    }
}
