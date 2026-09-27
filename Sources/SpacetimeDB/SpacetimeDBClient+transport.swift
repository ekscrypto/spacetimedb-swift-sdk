//
//  SpacetimeDBClient+transport.swift
//  spacetimedb-swift-sdk
//
//  Transport lifecycle callbacks from `NWWebSocketConnection`.
//
//  Created by Dave Poirier on 2026-09-26.
//

import Foundation

extension SpacetimeDBClient {
    // MARK: - Transport events

    internal func handleTransportEvent(_ event: NWWebSocketConnection.Event) async {
        switch event {
        case .connected:
            await websocketConnected()
        case .closed:
            await websocketDisconnected(reason: nil)
        case .failed(let reason):
            // Carry the failure text (e.g. "server refused the upgrade:
            // HTTP/1.1 401 …") onto `connectionEvents` — swallowing it made
            // an auth rejection indistinguishable from any network loss.
            await websocketDisconnected(reason: reason)
        }
    }

    internal func websocketConnected() async {
        _connected = true
        await clientDelegate?.onConnect(client: self)
    }

    internal func websocketDisconnected(reason: String?) async {
        _connected = false
        receiveTask?.cancel()
        receiveTask = nil
        wsConnection?.close()
        wsConnection = nil

        let clientDelegate = self.clientDelegate

        // Don't clear the delegate if we're going to reconnect
        if !shouldReconnect {
            self.clientDelegate = nil
        }

        // A transport death ends this connection's request ids: in-flight
        // reducer calls / one-offs / subscription futures can never resolve
        // on a new socket, so fail them here (they'd otherwise hang their
        // callers forever), and surface the loss on `connectionEvents` —
        // the async surface's only lifecycle signal. `disconnect()` emits
        // and fails the same things itself, so a manual disconnect may see
        // this run a second time (both are idempotent; consumers treat the
        // first terminal event as the end).
        self.emit(connection: .disconnected(reason: reason))
        self.failAllSubscriptionFutures(reason: reason.map { "connection lost: \($0)" } ?? "connection lost")

        await clientDelegate?.onDisconnect(client: self)

        // Start reconnection if enabled
        if shouldReconnect {
            startReconnection()
        }
    }
}
