//
//  UnsubscribeRequest.swift
//  spacetimedb-swift-sdk
//
//  v2 Unsubscribe message — see crates/client-api-messages/src/websocket/v2.rs
//  Wire: tag (u8=0x01) + request_id (u32) + query_set_id (u32) + flags (u8)
//

import Foundation
import BSATN

struct UnsubscribeRequest {
    let requestId: UInt32
    let querySetId: QuerySetId
    let flags: UnsubscribeFlags

    func encode() throws -> Data {
        let writer = BSATNWriter()
        writer.write(Tags.ClientMessage.unsubscribe.rawValue)
        writer.write(requestId)
        querySetId.encode(to: writer)
        flags.encode(to: writer)
        return writer.finalize()
    }
}
