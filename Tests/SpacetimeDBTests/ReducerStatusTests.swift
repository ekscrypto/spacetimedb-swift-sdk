import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("ReducerStatus + delegate bridging Tests")
struct ReducerStatusTests {

    @Test func updateStatusToReducerStatusCommitted() {
        let dbu = DatabaseUpdate(tableUpdates: [])
        let s: UpdateStatus = .committed(dbu)
        #expect(s.reducerStatus == .committed)
        #expect(s.reducerStatus.isCommitted)
        #expect(s.reducerStatus.failureMessage == nil)
    }

    @Test func updateStatusToReducerStatusFailed() {
        let s: UpdateStatus = .failed("boom")
        #expect(s.reducerStatus == .failed("boom"))
        #expect(!s.reducerStatus.isCommitted)
        #expect(s.reducerStatus.failureMessage == "boom")
    }

    @Test func updateStatusToReducerStatusOutOfEnergy() {
        let s: UpdateStatus = .outOfEnergy
        #expect(s.reducerStatus == .outOfEnergy)
        #expect(!s.reducerStatus.isCommitted)
        #expect(s.reducerStatus.failureMessage == nil)
    }

    /// Verify the protocol's typed-method default implementation bridges
    /// to the legacy string-status method, so existing delegates continue
    /// to receive reducer responses unchanged.
    @Test func typedDefaultBridgesToLegacyMethod() async throws {
        actor LegacyOnlyDelegate: SpacetimeDBClientDelegate {
            var captured: (reducer: String, requestId: UInt32, status: String, message: String?, energy: UInt128)?

            func record(_ tuple: (String, UInt32, String, String?, UInt128)) {
                self.captured = tuple
            }

            nonisolated func onConnect(client: SpacetimeDBClient) async {}
            nonisolated func onError(client: SpacetimeDBClient, error: any Error) async {}
            nonisolated func onDisconnect(client: SpacetimeDBClient) async {}
            nonisolated func onReconnecting(client: SpacetimeDBClient, attempt: Int) async {}
            nonisolated func onIncomingMessage(client: SpacetimeDBClient, message: Data) async {}
            nonisolated func onSubscribeMultiApplied(client: SpacetimeDBClient, queryId: UInt32) {}
            nonisolated func onIdentityReceived(client: SpacetimeDBClient, token: String, identity: BSATN.UInt256) async {}
            nonisolated func onTableUpdate(client: SpacetimeDBClient, table: String, deletes: [Any], inserts: [Any]) async {}

            // Only the legacy method is overridden; typed-method default impl must bridge.
            func onReducerResponse(client: SpacetimeDBClient, reducer: String, requestId: UInt32, status: String, message: String?, energyUsed: UInt128) async {
                await record((reducer, requestId, status, message, energyUsed))
            }
        }

        let delegate = LegacyOnlyDelegate()
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let energy = TransactionUpdate.EnergyQuanta.zero

        // Failed
        await delegate.onReducerResponse(
            client: client,
            requestId: 7,
            reducerName: "send_message",
            status: .failed("nope"),
            energy: energy
        )
        var captured = await delegate.captured
        #expect(captured?.reducer == "send_message")
        #expect(captured?.requestId == 7)
        #expect(captured?.status == "failed: nope")
        #expect(captured?.message == "nope")

        // Committed
        await delegate.onReducerResponse(
            client: client,
            requestId: 8,
            reducerName: "set_name",
            status: .committed,
            energy: energy
        )
        captured = await delegate.captured
        #expect(captured?.status == "committed")
        #expect(captured?.message == nil)

        // OutOfEnergy
        await delegate.onReducerResponse(
            client: client,
            requestId: 9,
            reducerName: "x",
            status: .outOfEnergy,
            energy: energy
        )
        captured = await delegate.captured
        #expect(captured?.status == "out of energy")
        #expect(captured?.message == nil)
    }

    @Test func clientIdentityAndConnectionIdNilBeforeConnect() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        let identity = await client.identity
        let connId = await client.connectionId
        #expect(identity == nil)
        #expect(connId == nil)
    }
}

extension TransactionUpdate.EnergyQuanta {
    static var zero: TransactionUpdate.EnergyQuanta {
        // Used by tests only; real instances are constructed from the wire.
        // Build via JSONEncoder/Decoder isn't available, so use a minimal
        // BSATN reader feeding 16 zero bytes (the EnergyQuanta wire shape:
        // a single u128).
        let zeroes = Data(repeating: 0, count: 16)
        let reader = BSATNReader(data: zeroes)
        return try! TransactionUpdate.EnergyQuanta(reader: reader)
    }
}
