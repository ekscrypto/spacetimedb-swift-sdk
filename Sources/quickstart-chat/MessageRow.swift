//
//  MessageRow.swift
//  quickstart-chat
//

import Foundation
import BSATN
import SpacetimeDB

struct MessageRow: BSATNRow {
    static let tableName = "message"

    let sender: UInt256
    let sent: UInt64
    let text: String

    init(reader: BSATNReader) throws {
        self.sender = try reader.read()
        self.sent = try reader.read()
        self.text = try reader.readString()
    }
}
