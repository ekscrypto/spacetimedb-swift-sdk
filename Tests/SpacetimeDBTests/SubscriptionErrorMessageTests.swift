import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("SubscriptionError Message Tests")
struct SubscriptionErrorMessageTests {

    @Test func decodesAllFieldsPresent() throws {
        let writer = BSATNWriter()
        writer.write(UInt64(12345))                // total_host_execution_duration_micros
        writer.write(UInt8(0)); writer.write(UInt32(42))      // request_id: Some(42)
        writer.write(UInt8(0)); writer.write(UInt32(7))       // query_id: Some(7)
        writer.write(UInt8(0)); writer.write(UInt32(4096))    // table_id: Some(4096)
        try writer.write("query parse failed: unknown table")  // error

        let reader = BSATNReader(data: writer.finalize())
        let message = try SubscriptionErrorMessage(reader: reader)

        #expect(message.totalHostExecutionDurationMicros == 12345)
        #expect(message.requestId == 42)
        #expect(message.queryId == 7)
        #expect(message.tableId == 4096)
        #expect(message.error == "query parse failed: unknown table")
    }

    @Test func decodesAllOptionalsAbsent() throws {
        // Server-emitted error from a transaction update path: no client request
        // and no specific table → all three Option fields are None.
        let writer = BSATNWriter()
        writer.write(UInt64(99))
        writer.write(UInt8(1))       // request_id: None
        writer.write(UInt8(1))       // query_id: None
        writer.write(UInt8(1))       // table_id: None
        try writer.write("server-side validation failed")

        let reader = BSATNReader(data: writer.finalize())
        let message = try SubscriptionErrorMessage(reader: reader)

        #expect(message.requestId == nil)
        #expect(message.queryId == nil)
        #expect(message.tableId == nil)
        #expect(message.error == "server-side validation failed")
    }

    @Test func decodesPartialOptionals() throws {
        // table_id absent but request_id and query_id present (table-scoped error
        // would set table_id; this represents a whole-subscription failure).
        let writer = BSATNWriter()
        writer.write(UInt64(500))
        writer.write(UInt8(0)); writer.write(UInt32(101))
        writer.write(UInt8(0)); writer.write(UInt32(202))
        writer.write(UInt8(1))       // table_id: None
        try writer.write("subscription dropped")

        let reader = BSATNReader(data: writer.finalize())
        let message = try SubscriptionErrorMessage(reader: reader)

        #expect(message.requestId == 101)
        #expect(message.queryId == 202)
        #expect(message.tableId == nil)
        #expect(message.error == "subscription dropped")
    }

    @Test func decodesEmptyErrorString() throws {
        let writer = BSATNWriter()
        writer.write(UInt64(0))
        writer.write(UInt8(1))
        writer.write(UInt8(1))
        writer.write(UInt8(1))
        try writer.write("")

        let reader = BSATNReader(data: writer.finalize())
        let message = try SubscriptionErrorMessage(reader: reader)

        #expect(message.error == "")
    }

    @Test func decodesUnicodeError() throws {
        let writer = BSATNWriter()
        writer.write(UInt64(1))
        writer.write(UInt8(1))
        writer.write(UInt8(1))
        writer.write(UInt8(1))
        try writer.write("クエリ失敗 ❌")

        let reader = BSATNReader(data: writer.finalize())
        let message = try SubscriptionErrorMessage(reader: reader)

        #expect(message.error == "クエリ失敗 ❌")
    }

    @Test func handlesMaximumValues() throws {
        let writer = BSATNWriter()
        writer.write(UInt64.max)
        writer.write(UInt8(0)); writer.write(UInt32.max)
        writer.write(UInt8(0)); writer.write(UInt32.max)
        writer.write(UInt8(0)); writer.write(UInt32.max)
        try writer.write("boom")

        let reader = BSATNReader(data: writer.finalize())
        let message = try SubscriptionErrorMessage(reader: reader)

        #expect(message.totalHostExecutionDurationMicros == UInt64.max)
        #expect(message.requestId == UInt32.max)
        #expect(message.queryId == UInt32.max)
        #expect(message.tableId == UInt32.max)
    }
}
