//
//  ConnectionId.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-09.
//

import Foundation

public struct ConnectionId: RawRepresentable, Codable, Equatable, Hashable {
    public let rawValue: Data

    public init() {
        rawValue = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    }

    public init(rawValue: Data) {
        if rawValue.count == 16 {
            self.rawValue = rawValue
        } else {
            self = ConnectionId()
        }
    }

    internal var hexRepresentation: String {
        rawValue.map { String(format: "%02x", $0) }.joined()
    }
}
