//
//  SendMessageReducer.swift
//  quickstart-chat
//
//  Created by Assistant on 2025-08-25.
//

import Foundation
import SpacetimeDB
import BSATN

/// Reducer for sending a message in the quickstart-chat database
public struct SendMessageReducer: Reducer {
    public let name = "send_message"
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public func encodeArguments(writer: BSATNWriter) throws {
        try writer.write(text)
    }
}