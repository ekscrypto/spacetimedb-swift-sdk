//
//  UserRow.swift
//  quickstart-chat
//

import Foundation
import BSATN
import SpacetimeDB

struct UserRow: BSATNRow {
    static let tableName = "user"

    let identity: UInt256
    let name: String?
    let online: Bool

    init(reader: BSATNReader) throws {
        self.identity = try reader.read()
        self.name = try reader.readOptional { try reader.readString() }
        self.online = try reader.read()
    }
}
