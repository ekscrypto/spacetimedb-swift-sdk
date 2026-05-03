import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

/// Live integration tests against a published maincloud module. Skipped
/// unless `SPACETIMEDB_LIVE=1` is set in the environment, so CI / day-to-day
/// `swift test` runs stay hermetic.
@Suite("Live maincloud smoke (set SPACETIMEDB_LIVE=1 to enable)")
struct MaincloudSmokeTest {

    static let host = ProcessInfo.processInfo.environment["SPACETIMEDB_HOST"]
        ?? "https://maincloud.spacetimedb.com"
    static let db = ProcessInfo.processInfo.environment["SPACETIMEDB_DB"]
        ?? "quickstart-chat-55kji"
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["SPACETIMEDB_LIVE"] == "1"
    }

    /// Handle-based subscribe API: `applied()` round-trips to the live
    /// server, then `unsubscribe()` round-trips back. End-to-end assertion.
    @Test(.enabled(if: MaincloudSmokeTest.enabled))
    func subscribeAppliedThenUnsubscribeRoundTrip() async throws {
        let client = try SpacetimeDBClient(host: Self.host, db: Self.db)
        let connected = await client.connectionEvents

        // Connect with a no-op delegate to exercise the delegate path
        // alongside the AsyncStream surface.
        actor NoopDelegate: SpacetimeDBClientDelegate {
            nonisolated func onConnect(client: SpacetimeDBClient) async {}
            nonisolated func onError(client: SpacetimeDBClient, error: any Error) async {}
            nonisolated func onDisconnect(client: SpacetimeDBClient) async {}
            nonisolated func onReconnecting(client: SpacetimeDBClient, attempt: Int) async {}
            nonisolated func onIncomingMessage(client: SpacetimeDBClient, message: Data) async {}
            nonisolated func onSubscribeMultiApplied(client: SpacetimeDBClient, queryId: UInt32) {}
            nonisolated func onIdentityReceived(client: SpacetimeDBClient, token: String, identity: BSATN.UInt256) async {}
            nonisolated func onTableUpdate(client: SpacetimeDBClient, table: String, deletes: [Any], inserts: [Any]) async {}
            nonisolated func onReducerResponse(client: SpacetimeDBClient, reducer: String, requestId: UInt32, status: String, message: String?, energyUsed: UInt128) async {}
        }
        let delegate = NoopDelegate()
        try await client.connect(token: nil, timeout: 10.0, delegate: delegate, enableAutoReconnect: false)

        // Wait for the IdentityToken before subscribing.
        var identityReceived = false
        for await event in connected {
            if case .connected = event {
                identityReceived = true
                break
            }
        }
        #expect(identityReceived)

        let handle = try await client.subscribe(["SELECT * FROM user"])
        try await handle.applied()
        try await handle.unsubscribe()
        await client.disconnect()
    }
}
