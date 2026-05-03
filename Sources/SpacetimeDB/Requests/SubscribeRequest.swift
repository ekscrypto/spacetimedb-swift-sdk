//
//  SubscribeRequest.swift
//  spacetimedb-swift-sdk
//
//  v2 Subscribe message — see crates/client-api-messages/src/websocket/v2.rs
//  Wire: tag (u8=0x00) + request_id (u32) + query_set_id (u32) + query_strings ([]string)
//

import Foundation
import BSATN

struct SubscribeRequest {
    let requestId: UInt32
    let querySetId: QuerySetId
    let queryStrings: [String]

    func encode() throws -> Data {
        let writer = BSATNWriter()
        writer.write(Tags.ClientMessage.subscribe.rawValue)
        writer.write(requestId)
        querySetId.encode(to: writer)
        writer.write(UInt32(queryStrings.count))
        for query in queryStrings {
            try writer.write(query)
        }
        return writer.finalize()
    }
}
