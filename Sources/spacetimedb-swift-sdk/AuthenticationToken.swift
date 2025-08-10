//
//  AuthenticationToken.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-09.
//

import Foundation

public struct AuthenticationToken: RawRepresentable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
