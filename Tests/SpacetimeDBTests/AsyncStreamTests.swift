import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("AsyncStream event surface Tests")
struct AsyncStreamTests {

    @Test func connectionEventsMultiSubscriberFanOut() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")

        let s1 = await client.connectionEvents
        let s2 = await client.connectionEvents

        let identity = try #require(Identity(hex: String(repeating: "0", count: 64)))
        let connId = try #require(ConnectionId(hexString: String(repeating: "0", count: 32)))
        await client.emit(connection: .connected(identity: identity, connectionId: connId, token: "tok"))
        await client.emit(connection: .reconnecting(attempt: 3))

        var i1 = s1.makeAsyncIterator()
        var i2 = s2.makeAsyncIterator()

        let e1a = await i1.next()
        let e1b = await i1.next()
        let e2a = await i2.next()
        let e2b = await i2.next()

        if case .connected(let id, _, let tok) = e1a {
            #expect(id == identity)
            #expect(tok == "tok")
        } else { Issue.record("Expected .connected on s1, got \(String(describing: e1a))") }

        if case .reconnecting(let attempt) = e1b {
            #expect(attempt == 3)
        } else { Issue.record("Expected .reconnecting on s1, got \(String(describing: e1b))") }

        if case .connected = e2a { } else { Issue.record("Expected .connected on s2") }
        if case .reconnecting(let attempt) = e2b {
            #expect(attempt == 3)
        } else { Issue.record("Expected .reconnecting on s2") }
    }

    @Test func reducerEventStreamReceivesEmissions() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let stream = await client.reducerEvents

        let event = ReducerEvent(
            requestId: 42,
            reducerName: "send_message",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            outcome: .internalError("nope")
        )
        await client.emit(reducer: event)

        var iter = stream.makeAsyncIterator()
        let received = await iter.next()
        #expect(received?.requestId == 42)
        #expect(received?.reducerName == "send_message")
        if case .internalError(let msg) = received?.outcome {
            #expect(msg == "nope")
        } else {
            Issue.record("Expected .internalError outcome")
        }
    }

    @Test func subscriptionLifecycleStream() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let stream = await client.subscriptionEvents

        await client.emit(subscription: .applied(queryId: 1))
        await client.emit(subscription: .unsubscribed(queryId: 1))
        await client.emit(subscription: .error(queryId: 7, requestId: nil, message: "boom"))

        var iter = stream.makeAsyncIterator()
        #expect(await iter.next() == .applied(queryId: 1))
        #expect(await iter.next() == .unsubscribed(queryId: 1))
        #expect(await iter.next() == .error(queryId: 7, requestId: nil, message: "boom"))
    }

    @Test func tableEventsBucketed() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let userStream = await client.tableEvents(named: "user")
        let messageStream = await client.tableEvents(named: "message")

        await client.emit(tableEvent: TableEvent(tableName: "user", deletes: [], inserts: ["alice", "bob"]))
        await client.emit(tableEvent: TableEvent(tableName: "message", deletes: [], inserts: ["hello"]))

        var ui = userStream.makeAsyncIterator()
        var mi = messageStream.makeAsyncIterator()

        let userEvent = try #require(await ui.next())
        #expect(userEvent.tableName == "user")
        #expect(userEvent.inserts.count == 2)

        let msgEvent = try #require(await mi.next())
        #expect(msgEvent.tableName == "message")
        #expect(msgEvent.inserts.count == 1)
    }

    @Test func cancellingConsumerUnregistersContinuation() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")

        let consumerTask = Task {
            for await _ in await client.connectionEvents {}
        }
        try await Task.sleep(nanoseconds: 25_000_000)

        let beforeCancel = await client.connectionContinuationCount
        #expect(beforeCancel >= 1)

        consumerTask.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)

        let afterCancel = await client.connectionContinuationCount
        #expect(afterCancel == 0)
    }

    /// Regression test for the original stream-registration race: emitting
    /// an event the instant after the stream accessor returns must not be lost.
    @Test func emitImmediatelyAfterAccessIsNotLost() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let stream = await client.subscriptionEvents
        await client.emit(subscription: .applied(queryId: 99))
        var iter = stream.makeAsyncIterator()
        let event = await iter.next()
        #expect(event == .applied(queryId: 99))
    }
}

extension SpacetimeDBClient {
    var connectionContinuationCount: Int { connectionContinuations.count }
}
