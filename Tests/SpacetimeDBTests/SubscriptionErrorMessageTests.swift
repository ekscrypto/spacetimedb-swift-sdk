import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("SubscriptionError Message Tests")
struct SubscriptionErrorMessageTests {

    /// Wire shape: request_id (Option<u32>) + query_set_id (u32) + error (string).
    /// Errors are scoped by query_set_id only.

    @Test func decodesWithRequestIdPresent() throws {
        // Response to a client-issued Subscribe.
        let writer = BSATNWriter()
        writer.write(UInt8(0))                  // request_id = Some
        writer.write(UInt32(42))
        writer.write(UInt32(7))                 // query_set_id
        try writer.write("query parse failed: unknown table")

        let reader = BSATNReader(data: writer.finalize())
        let msg = try SubscriptionErrorMessage(reader: reader)

        #expect(msg.requestId == 42)
        #expect(msg.querySetId.id == 7)
        #expect(msg.error == "query parse failed: unknown table")
    }

    @Test func decodesWithRequestIdAbsent() throws {
        // Mid-subscription failure (e.g. query became invalid after applying).
        let writer = BSATNWriter()
        writer.write(UInt8(1))                  // request_id = None
        writer.write(UInt32(99))                // query_set_id
        try writer.write("server-side validation failed")

        let reader = BSATNReader(data: writer.finalize())
        let msg = try SubscriptionErrorMessage(reader: reader)

        #expect(msg.requestId == nil)
        #expect(msg.querySetId.id == 99)
        #expect(msg.error == "server-side validation failed")
    }

    @Test func decodesEmptyErrorString() throws {
        let writer = BSATNWriter()
        writer.write(UInt8(1))   // request_id None
        writer.write(UInt32(0))
        try writer.write("")

        let reader = BSATNReader(data: writer.finalize())
        let msg = try SubscriptionErrorMessage(reader: reader)
        #expect(msg.error == "")
    }

    @Test func decodesUnicodeError() throws {
        let writer = BSATNWriter()
        writer.write(UInt8(1))
        writer.write(UInt32(1))
        try writer.write("クエリ失敗 ❌")

        let reader = BSATNReader(data: writer.finalize())
        let msg = try SubscriptionErrorMessage(reader: reader)
        #expect(msg.error == "クエリ失敗 ❌")
    }

    @Test func handlesMaximumValues() throws {
        let writer = BSATNWriter()
        writer.write(UInt8(0))
        writer.write(UInt32.max)
        writer.write(UInt32.max)
        try writer.write("boom")

        let reader = BSATNReader(data: writer.finalize())
        let msg = try SubscriptionErrorMessage(reader: reader)
        #expect(msg.requestId == UInt32.max)
        #expect(msg.querySetId.id == UInt32.max)
        #expect(msg.error == "boom")
    }
}
