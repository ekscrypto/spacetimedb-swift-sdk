//
//  SpacetimeDBClient+websocketdelegate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation

extension SpacetimeDBClient {
    // MARK: - Delegate callbacks
    internal func websocketConnected() async {
        _connected = true
        await clientDelegate?.onConnect(client: self)
    }

    internal func websocketDisconnected() async {
        _connected = false
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel()
        webSocketTask = nil

        let clientDelegate = self.clientDelegate
        self.clientDelegate = nil

        await clientDelegate?.onDisconnect(client: self)
    }
}
