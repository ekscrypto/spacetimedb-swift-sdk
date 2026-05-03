import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("SubscriptionHandle Tests")
struct SubscriptionHandleTests {

    /// `applied()` resolves when the matching `.applied` event arrives.
    @Test func appliedResolvesOnMatchingApplied() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let handle = SubscriptionHandle(queryId: 42, queries: ["SELECT * FROM x"], client: client)

        let waiter = Task { try await handle.applied() }
        try await Task.sleep(nanoseconds: 25_000_000)

        await client.resolveSubscriptionApplied(queryId: 42)
        try await waiter.value
    }

    /// `applied()` throws when the matching subscription error arrives.
    @Test func appliedThrowsOnMatchingError() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let handle = SubscriptionHandle(queryId: 7, queries: [], client: client)

        let waiter = Task { try await handle.applied() }
        try await Task.sleep(nanoseconds: 25_000_000)

        await client.failSubscriptionFutures(queryId: 7, message: "boom")

        await #expect(throws: SpacetimeDBError.self) {
            try await waiter.value
        }
    }

    /// Handle's `events` stream filters to its own queryId.
    @Test func eventsStreamFiltersByQueryId() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let handle = SubscriptionHandle(queryId: 100, queries: [], client: client)

        let stream = await handle.events()

        await client.emit(subscription: .applied(queryId: 99))           // foreign — filtered
        await client.emit(subscription: .applied(queryId: 100))          // ours — pass
        await client.emit(subscription: .unsubscribed(queryId: 100))

        var iter = stream.makeAsyncIterator()
        let first = await iter.next()
        let second = await iter.next()

        #expect(first == .applied(queryId: 100))
        #expect(second == .unsubscribed(queryId: 100))
    }

    /// Subscription error scoped to this handle's queryId reaches it.
    @Test func errorPropagatesToHandle() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let handle = SubscriptionHandle(queryId: 1, queries: [], client: client)

        let stream = await handle.events()
        await client.emit(subscription: .error(queryId: 1, requestId: 99, message: "wide"))

        var iter = stream.makeAsyncIterator()
        let event = await iter.next()
        #expect(event == .error(queryId: 1, requestId: 99, message: "wide"))
    }
}
