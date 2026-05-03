import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("SubscriptionHandle Tests")
struct SubscriptionHandleTests {

    /// `applied()` resolves when the matching `.applied` event arrives.
    @Test func appliedResolvesOnMatchingApplied() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let handle = SubscriptionHandle(queryId: 42, isMulti: true, queries: ["SELECT * FROM x"], client: client)

        let waiter = Task { try await handle.applied() }
        // Yield once so the waiter Task gets a chance to register its
        // pending-applied continuation before we resolve it.
        try await Task.sleep(nanoseconds: 25_000_000)

        await client.resolveSubscriptionApplied(queryId: 42)
        try await waiter.value   // should not throw
    }

    /// `applied()` throws when the matching subscription error arrives.
    @Test func appliedThrowsOnMatchingError() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let handle = SubscriptionHandle(queryId: 7, isMulti: true, queries: [], client: client)

        let waiter = Task { try await handle.applied() }
        try await Task.sleep(nanoseconds: 25_000_000)

        await client.failSubscriptionFutures(queryId: 7, message: "boom")

        await #expect(throws: SpacetimeDBError.self) {
            try await waiter.value
        }
    }

    /// Handle's `events` stream filters to its own queryId. No sleep
    /// needed: `events()` is async so upstream registration completes
    /// before any emit can race past it.
    @Test func eventsStreamFiltersByQueryId() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let handle = SubscriptionHandle(queryId: 100, isMulti: true, queries: [], client: client)

        let stream = await handle.events()

        await client.emit(subscription: .applied(queryId: 99, multi: true))     // foreign — filtered
        await client.emit(subscription: .applied(queryId: 100, multi: true))    // ours — pass
        await client.emit(subscription: .unsubscribed(queryId: 100, multi: true))

        var iter = stream.makeAsyncIterator()
        let first = await iter.next()
        let second = await iter.next()

        #expect(first == .applied(queryId: 100, multi: true))
        #expect(second == .unsubscribed(queryId: 100, multi: true))
    }

    /// Connection-wide subscription error (queryId == nil) reaches every handle.
    @Test func connectionWideErrorPropagatesToHandle() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let handle = SubscriptionHandle(queryId: 1, isMulti: true, queries: [], client: client)

        let stream = await handle.events()

        await client.emit(subscription: .error(queryId: nil, tableId: nil, message: "wide"))

        var iter = stream.makeAsyncIterator()
        let event = await iter.next()
        #expect(event == .error(queryId: nil, tableId: nil, message: "wide"))
    }
}
