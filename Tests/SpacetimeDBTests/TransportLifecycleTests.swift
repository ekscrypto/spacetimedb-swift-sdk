import Testing
import Foundation
import Network
@testable import SpacetimeDB
@testable import BSATN

/// Transport-lifecycle pins over a real loopback socket — the layer below
/// every app-side test double (the 2026-09 incidents lived exactly here).
///
/// The acceptor below completes the TCP handshake but never answers the
/// WebSocket upgrade, which is enough transport for the client to hold
/// pending futures (sends buffer until the upgrade completes), while
/// `.connected` can never fire. What these tests pin:
///
/// - `connect()` returns before the handshake — `.connected` is the
///   InitialConnection signal, not a return precondition;
/// - transport death fails pending reducer calls, one-off queries, and
///   subscription futures with `SpacetimeDBError.disconnected`, and
///   surfaces `.disconnected` on `connectionEvents`.
///
/// Not covered here (needs a speaking loopback server): snapshot fan-out
/// ordering around `subscribe`, and live compression negotiation.
@Suite("Transport lifecycle Tests")
struct TransportLifecycleTests {

    /// A loopback TCP listener that accepts and holds connections without
    /// ever completing the WebSocket upgrade.
    private final class HoldingAcceptor: @unchecked Sendable {
        let listener: NWListener
        private let lock = NSLock()
        private var held: [NWConnection] = []
        private var readyContinuations: [CheckedContinuation<Void, Never>] = []

        init() throws {
            listener = try NWListener(using: .tcp)
        }

        var port: UInt16 { listener.port?.rawValue ?? 0 }

        func start() async {
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global())
                self?.hold(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state { self?.resumeReady() }
            }
            listener.start(queue: .global())
            await withCheckedContinuation { continuation in
                let alreadyReady: Bool = lock.withLock {
                    if case .ready = listener.state { return true }
                    readyContinuations.append(continuation)
                    return false
                }
                if alreadyReady { continuation.resume() }
            }
        }

        func stop() {
            listener.cancel()
            let connections = lock.withLock {
                let copy = held
                held = []
                return copy
            }
            connections.forEach { $0.cancel() }
        }

        private func hold(_ connection: NWConnection) {
            lock.withLock { held.append(connection) }
        }

        private func resumeReady() {
            let continuations = lock.withLock {
                let copy = readyContinuations
                readyContinuations = []
                return copy
            }
            continuations.forEach { $0.resume() }
        }
    }

    private func makeClient(on acceptor: HoldingAcceptor) throws -> SpacetimeDBClient {
        try SpacetimeDBClient(host: "ws://127.0.0.1:\(acceptor.port)", db: "transport-tests")
    }

    /// `connect()` returns before the handshake: against an acceptor that
    /// never upgrades, it must return promptly, and the first lifecycle
    /// signal on `connectionEvents` is the failure — never `.connected`.
    @Test func connectReturnsBeforeTheHandshakeCompletes() async throws {
        let acceptor = try HoldingAcceptor()
        await acceptor.start()
        defer { acceptor.stop() }

        let client = try makeClient(on: acceptor)
        let events = await client.connectionEvents

        let started = Date()
        try await client.connect(timeout: 5, enableAutoReconnect: false)
        #expect(Date().timeIntervalSince(started) < 1.0)

        // Give the (never-completing) upgrade ample time to misreport, then
        // end the transport; the first observed event must be the loss —
        // `.connected` never fired despite connect() having returned.
        try await Task.sleep(nanoseconds: 200_000_000)
        await client.handleTransportEvent(.failed("test: handshake never answered"))

        var iterator = events.makeAsyncIterator()
        let first = await iterator.next()
        guard case .disconnected = first else {
            Issue.record("expected .disconnected as the first connection event, got \(String(describing: first))")
            return
        }
    }

    /// Transport death fails every pending future — reducer call, one-off
    /// query, and subscription `applied()` — with `SpacetimeDBError`,
    /// instead of hanging their callers forever.
    @Test func transportDeathFailsPendingCallsAndSurfacesTheLoss() async throws {
        let acceptor = try HoldingAcceptor()
        await acceptor.start()
        defer { acceptor.stop() }

        let client = try makeClient(on: acceptor)
        let events = await client.connectionEvents
        try await client.connect(timeout: 5, enableAutoReconnect: false)

        // Three flavors of pending future. Sends buffer behind the
        // (never-completing) upgrade, so all of them stay pending until
        // the transport dies.
        let handle = SubscriptionHandle(queryId: 42, queries: ["SELECT * FROM x"], client: client)
        let applied = Task { try await handle.applied() }
        let reducer = Task { try await client.callReducer(name: "noop") }
        let oneOff = Task { try await client.oneOffQuery("SELECT * FROM x", timeout: 60) }
        try await Task.sleep(nanoseconds: 150_000_000)

        await client.handleTransportEvent(.failed("test: transport death"))

        await #expect(throws: SpacetimeDBError.self) { try await applied.value }
        await #expect(throws: SpacetimeDBError.self) { try await reducer.value }
        await #expect(throws: SpacetimeDBError.self) { try await oneOff.value }

        var iterator = events.makeAsyncIterator()
        let event = await iterator.next()
        guard case .disconnected = event else {
            Issue.record("expected .disconnected on connectionEvents, got \(String(describing: event))")
            return
        }
    }
}
