import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("Phase 14: TransactionEvent stream")
struct TransactionEventTests {

    @Test func transactionEventStreamReceivesEmissions() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let stream = await client.transactionEvents

        let event = TransactionEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            querySetCount: 2,
            affectedTables: ["user", "message"]
        )
        await client.emit(transaction: event)

        var iter = stream.makeAsyncIterator()
        let received = await iter.next()
        #expect(received?.querySetCount == 2)
        #expect(received?.affectedTables == ["user", "message"])
    }

    @Test func cancellingTransactionConsumerUnregistersContinuation() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let consumer = Task {
            for await _ in await client.transactionEvents {}
        }
        try await Task.sleep(nanoseconds: 25_000_000)

        let beforeCancel = await client.transactionContinuationCount
        #expect(beforeCancel >= 1)

        consumer.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)

        let afterCancel = await client.transactionContinuationCount
        #expect(afterCancel == 0)
    }
}

extension SpacetimeDBClient {
    var transactionContinuationCount: Int { transactionContinuations.count }
}
