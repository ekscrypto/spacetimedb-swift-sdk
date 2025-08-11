//
//  SpacetimeDBClientDelegate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation

public protocol SpacetimeDBClientDelegate: AnyObject, Sendable {
    func onConnect() async
    func onError(_ error: any Error) async
    func onDisconnect() async
    func onIncomingMessage(_ message: Data) async
}
