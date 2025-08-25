//
//  SpacetimeDBClient+disconnect.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-24.
//

import Foundation

extension SpacetimeDBClient {
    /// Disconnect from the SpacetimeDB server
    public func disconnect() async {
        if let task = webSocketTask {
            task.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
        }
        
        _connected = false
        
        // Notify delegate
        if let delegate = clientDelegate {
            await delegate.onDisconnect(client: self)
        }
    }
}