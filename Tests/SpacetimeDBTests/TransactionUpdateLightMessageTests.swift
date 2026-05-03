import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("TransactionUpdateLight Message Tests")
struct TransactionUpdateLightMessageTests {

    @Test func decodesEmptyUpdate() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(7))      // request_id
        writer.write(UInt32(0))      // 0 table updates

        let reader = BSATNReader(data: writer.finalize())
        let message = try TransactionUpdateLightMessage(reader: reader)

        #expect(message.requestId == 7)
        #expect(message.update.tableUpdates.isEmpty)
    }

    @Test func decodesSingleTableUpdate() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(42))     // request_id
        writer.write(UInt32(1))      // 1 table update

        // TableUpdate
        writer.write(UInt32(4096))   // table id
        try writer.write("user")
        writer.write(UInt64(0))      // num_rows
        writer.write(UInt32(0))      // 0 query updates

        let reader = BSATNReader(data: writer.finalize())
        let message = try TransactionUpdateLightMessage(reader: reader)

        #expect(message.requestId == 42)
        #expect(message.update.tableUpdates.count == 1)
        #expect(message.update.tableUpdates[0].id == 4096)
        #expect(message.update.tableUpdates[0].name == "user")
    }

    @Test func decodesMultipleTableUpdates() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(99))
        writer.write(UInt32(2))      // 2 table updates

        writer.write(UInt32(100))
        try writer.write("user")
        writer.write(UInt64(0))
        writer.write(UInt32(0))

        writer.write(UInt32(101))
        try writer.write("message")
        writer.write(UInt64(0))
        writer.write(UInt32(0))

        let reader = BSATNReader(data: writer.finalize())
        let message = try TransactionUpdateLightMessage(reader: reader)

        #expect(message.update.tableUpdates.count == 2)
        #expect(message.update.tableUpdates[0].name == "user")
        #expect(message.update.tableUpdates[1].name == "message")
    }

    @Test func handlesMaxRequestId() throws {
        let writer = BSATNWriter()
        writer.write(UInt32.max)
        writer.write(UInt32(0))

        let reader = BSATNReader(data: writer.finalize())
        let message = try TransactionUpdateLightMessage(reader: reader)

        #expect(message.requestId == UInt32.max)
    }

    @Test func differsFromFullTransactionUpdate() throws {
        // TransactionUpdateLight has only request_id + DatabaseUpdate, while
        // full TransactionUpdate adds status, timestamp, caller, energy, etc.
        // Encoding only the light fields and reading it as light succeeds.
        let writer = BSATNWriter()
        writer.write(UInt32(1))
        writer.write(UInt32(0))

        let reader = BSATNReader(data: writer.finalize())
        let message = try TransactionUpdateLightMessage(reader: reader)
        #expect(message.requestId == 1)
        #expect(message.update.tableUpdates.isEmpty)
    }
}
