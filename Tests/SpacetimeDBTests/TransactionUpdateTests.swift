import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("Transaction Update Tests")
struct TransactionUpdateTests {

    @Test func parseTransactionUpdateFromRealBytes() throws {
        // The actual bytes received from the server for a TransactionUpdate message
        let hexString = """
        00 01 00 01 00 00 00 01 10 00 00 07 00 00 00 6D
        65 73 73 61 67 65 01 00 00 00 00 00 00 00 01 00
        00 00 00 01 00 00 00 00 00 00 00 00 01 01 00 00
        00 00 00 00 00 00 00 00 00 43 00 00 00 22 30 3D
        DA 34 93 14 32 98 15 2C 33 F2 13 0B 61 0B F7 AA
        6A CA 94 DA 37 BE E3 EC A0 91 E8 00 C2 CE 80 9A
        DF 24 3D 06 00 17 00 00 00 48 65 6C 6C 6F 20 75
        73 65 72 20 63 32 30 30 30 63 32 65 32 31 39 33
        CE 80 9A DF 24 3D 06 00 22 30 3D DA 34 93 14 32
        98 15 2C 33 F2 13 0B 61 0B F7 AA 6A CA 94 DA 37
        BE E3 EC A0 91 E8 00 C2 41 BF 9C 46 5F 24 90 B5
        C7 04 E9 F0 E2 61 E8 FA 0C 00 00 00 73 65 6E 64
        5F 6D 65 73 73 61 67 65 02 00 00 00 1B 00 00 00
        17 00 00 00 48 65 6C 6C 6F 20 75 73 65 72 20 63
        32 30 30 30 63 32 65 32 31 39 33 00 00 00 00 A8
        2A 1E 00 00 00 00 00 00 00 00 00 00 00 00 00 B4
        02 00 00 00 00 00 00
        """

        // Convert hex string to Data
        let cleanHex = hexString.replacingOccurrences(of: " ", with: "")
                                .replacingOccurrences(of: "\n", with: "")
        var data = Data()
        var index = cleanHex.startIndex
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2)
            if let byte = UInt8(cleanHex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }

        print("Test data size: \(data.count) bytes")
        #expect(data.count == 263, "Expected 263 bytes of test data")

        // The first two bytes are compression (00) and message type (01)
        let reader = BSATNReader(data: data)

        // Read compression tag
        let compressionTag = try reader.read() as UInt8
        #expect(compressionTag == 0, "Expected no compression")

        // Read message type tag
        let messageTag = try reader.read() as UInt8
        #expect(messageTag == 1, "Expected TransactionUpdate message type")

        // Now parse the actual TransactionUpdate
        let remainingData = reader.remainingData()
        print("Remaining data for TransactionUpdate: \(remainingData.count) bytes")

        let update = try TransactionUpdate(data: remainingData)

        // Verify the parsed data
        #expect(update.eventStatusDescription == "committed", "Expected committed status")
        #expect(update.reducerName == "send_message", "Expected send_message reducer")

        // Check reducer args
        #expect(update.reducerArgs.count == 27, "Expected 27 bytes of reducer args")

        // The reducer args should contain the message "Hello user c2000c2e2193"
        // It's BSATN encoded, so we need to parse it
        let argsReader = BSATNReader(data: update.reducerArgs)
        let messageLength: UInt32 = try argsReader.read()
        #expect(messageLength == 23, "Expected message length of 23")
        let messageData = try argsReader.readBytes(Int(messageLength))
        let message = String(data: Data(messageData), encoding: .utf8)
        #expect(message == "Hello user c2000c2e2193", "Expected specific message content")

        // Check database updates
        #expect(update.databaseUpdate.tableUpdates.count == 1, "Expected 1 table update")

        let tableUpdate = update.databaseUpdate.tableUpdates[0]
        #expect(tableUpdate.name == "message", "Expected message table")
        #expect(tableUpdate.id == 4097, "Expected table ID 4097 (0x1001)")
        #expect(tableUpdate.queryUpdates.count == 1, "Expected 1 query update")

        // Get the query update
        let queryUpdate = try tableUpdate.getQueryUpdate()
        #expect(queryUpdate.inserts.rows.count == 1, "Expected 1 inserted row")
        #expect(queryUpdate.deletes.rows.count == 0, "Expected no deleted rows")

        // Check the inserted row data
        if let insertedRow = queryUpdate.inserts.rows.first {
            print("Inserted row size: \(insertedRow.count) bytes")
            // The actual server bytes contain 67 bytes of row data
            // This is the MessageRow data that was inserted
            #expect(insertedRow.count == 67, "Expected 67 bytes of row data for the inserted message")
        }

        print("✅ Successfully parsed TransactionUpdate from real server bytes!")
        print("  Reducer: \(update.reducerName)")
        print("  Message: \(message ?? "nil")")
        print("  Energy used: \(update.energyUsed.used)")
        print("  Tables updated: \(update.databaseUpdate.tableUpdates.map { $0.name })")
    }

    @Test func parseTransactionUpdateWithCurrentProtocol() throws {
        // Test with correctly structured TransactionUpdate for current protocol
        let writer = BSATNWriter()

        // 1. UpdateStatus (sum type)
        writer.write(UInt8(0))  // Tag 0 = committed
        // DatabaseUpdate inside committed status
        writer.write(UInt32(0))  // 0 table updates

        // 2. Timestamp
        writer.write(UInt64(1234567890))

        // 3. Caller identity (UInt256)
        writer.write(UInt256(u0: 1, u1: 2, u2: 3, u3: 4))

        // 4. Caller connection ID (UInt128)
        writer.write(UInt128(u0: 100, u1: 200))

        // 5. ReducerCallInfo
        writer.write(UInt32(7))  // reducer name length
        writer.writeBytes("message".data(using: .utf8)!)
        writer.write(UInt32(1))  // reducer ID
        writer.write(UInt32(11))  // args length
        writer.writeBytes("Hello world".data(using: .utf8)!)
        writer.write(UInt32(42))  // request ID

        // 6. EnergyQuanta (as UInt128)
        writer.write(UInt128(u0: 1000, u1: 0))

        // 7. Total host execution duration
        writer.write(UInt64(5000))

        let data = writer.finalize()
        let reader = BSATNReader(data: data)
        let transactionUpdate = try TransactionUpdate(reader: reader)

        // Verify parsing succeeded
        #expect(transactionUpdate.timestamp == 1234567890)
        #expect(transactionUpdate.reducerName == "message")
        #expect(transactionUpdate.totalHostExecutionDuration == 5000)

        if case .committed(_) = transactionUpdate.status {
            // Success
        } else {
            Issue.record("Expected committed status")
        }
    }
}