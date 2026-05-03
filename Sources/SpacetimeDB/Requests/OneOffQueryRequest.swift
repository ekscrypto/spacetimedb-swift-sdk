//
//  OneOffQueryRequest.swift
//  spacetimedb-swift-sdk
//
//  v2 OneOffQuery message — see crates/client-api-messages/src/websocket/v2.rs
//  Wire: tag (u8=0x02) + request_id (u32) + query_string (string)
//

import Foundation
import BSATN

struct OneOffQueryRequest {
    let requestId: UInt32
    let queryString: String

    func encode() throws -> Data {
        let writer = BSATNWriter()
        writer.write(Tags.ClientMessage.oneOffQuery.rawValue)
        writer.write(requestId)
        try writer.write(queryString)
        return writer.finalize()
    }
}
