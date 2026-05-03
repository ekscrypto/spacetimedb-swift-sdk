import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("BSATNEventRow / eventRows stream")
struct EventTableTests {

    struct TelemetryEventRow: BSATNEventRow, Equatable {
        static let tableName = "telemetry_event"
        let kind: String
        let value: UInt64

        init(kind: String, value: UInt64) {
            self.kind = kind
            self.value = value
        }

        init(reader: BSATNReader) throws {
            self.kind = try reader.readString()
            self.value = try reader.read()
        }
    }

    @Test func eventRowDecoderHasNoPrimaryKeyExtractor() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(TelemetryEventRow.self)
        let decoder = await client.decoder(forTable: "telemetry_event")
        // BSATNEventRow inherits from BSATNRow but does not provide a PK
        // extractor — `.deleted` rows in a transaction would not pair
        // with `.inserted` rows even if both were present.
        #expect(decoder?.primaryKeyExtractor == nil)
    }

    @Test func eventRowsStreamYieldsTypedRows() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(TelemetryEventRow.self)
        let stream = await client.eventRows(TelemetryEventRow.self)

        let first = TelemetryEventRow(kind: "boot", value: 1)
        let second = TelemetryEventRow(kind: "tick", value: 2)
        await client.emit(tableEvent: TableEvent(
            tableName: "telemetry_event",
            deletes: [],
            inserts: [first, second]
        ))

        var iter = stream.makeAsyncIterator()
        let r1 = try #require(await iter.next())
        let r2 = try #require(await iter.next())
        #expect(r1 == first)
        #expect(r2 == second)
    }

    @Test func eventRowsStreamFiltersOutNonInsertedEvents() async throws {
        // Defensive: even if a misconfigured server sent a delete, the
        // typed event-row stream should drop it rather than crash.
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(TelemetryEventRow.self)
        let stream = await client.eventRows(TelemetryEventRow.self)

        let dropped = TelemetryEventRow(kind: "should-not-arrive", value: 0)
        let kept = TelemetryEventRow(kind: "should-arrive", value: 1)
        await client.emit(tableEvent: TableEvent(
            tableName: "telemetry_event",
            deletes: [dropped],     // intentionally pumped through delete
            inserts: [kept]
        ))

        var iter = stream.makeAsyncIterator()
        let received = try #require(await iter.next())
        #expect(received == kept)
    }
}
