//
//  SetNameReducer.swift
//  quickstart-chat
//
//  Created by Dave Poirier on 2025-08-24.
//

import Foundation
import spacetimedb_swift_sdk
import BSATN

/// Reducer for setting a user's name in the quickstart-chat database
public struct SetNameReducer: Reducer {
    public let name = "set_name"
    public let userName: String
    
    public init(userName: String) {
        self.userName = userName
    }
    
    public func encodeArguments(writer: BSATNWriter) throws {
        try writer.write(userName)
    }
}