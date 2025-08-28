//
//  OneOffQueryRequest.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-27.
//

import Foundation
import BSATN

struct OneOffQueryRequest {
    let messageId: Data
    let queryString: String

    init(messageId: Data, queryString: String) {
        self.messageId = messageId
        self.queryString = queryString
    }

    func encode() throws -> Data {
        let writer = BSATNWriter()
        try writer.writeAlgebraicValue(.uint8(Tags.ClientMessage.oneOffQuery.rawValue))
        
        // Write message ID as array of bytes
        try writer.writeAlgebraicValue(.uint32(UInt32(messageId.count)))
        for byte in messageId {
            try writer.writeAlgebraicValue(.uint8(byte))
        }
        
        // Write query string as array of bytes
        let encoded = queryString.data(using: .utf8)!
        try writer.writeAlgebraicValue(.uint32(UInt32(encoded.count)))
        for byte in encoded {
            try writer.writeAlgebraicValue(.uint8(byte))
        }
        
        return writer.finalize()
    }
}