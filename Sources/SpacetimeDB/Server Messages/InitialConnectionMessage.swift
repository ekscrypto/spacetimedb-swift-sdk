//
//  InitialConnectionMessage.swift
//  spacetimedb-swift-sdk
//
//  v2 ServerMessage tag 0x00 — first message after a successful connection.
//  Replaces v1's IdentityToken; same payload shape (identity + connection
//  id + token) but with a more accurate name.
//
//  Wire: identity (u256) + connection_id (u128) + token (string)
//

import Foundation
import BSATN

struct InitialConnectionMessage: Sendable {
    let identity: UInt256
    let connectionId: UInt128
    let token: String

    init(reader: BSATNReader) throws {
        self.identity = try reader.read()
        self.connectionId = try reader.read()
        self.token = try reader.readString()
        debugLog(">>> InitialConnection: identity=\(identity.description.prefix(16))..., connectionId=\(connectionId), tokenLen=\(token.count)")
    }
}
