//
//  SubscribeRequest.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN

struct SubscribeMultiRequest {
    let queries: [String]
    let requestId: UInt32
    let queryId: UInt32

    func encode() throws -> Data {
        let writer = BSATNWriter()
        try writer.writeAlgebraicValue(.uint8(Tags.ClientMessage.subscribeMulti.rawValue))
        try writer.writeAlgebraicValue(.uint32(UInt32(queries.count)))
        for query in queries {
            let encoded = query.data(using: .utf8)!
            try writer.writeAlgebraicValue(.uint32(UInt32(encoded.count)))
            for byte in encoded {
                try writer.writeAlgebraicValue(.uint8(byte))
            }
        }
        try writer.writeAlgebraicValue(.uint32(requestId))
        try writer.writeAlgebraicValue(.uint32(queryId))
        return writer.finalize()
    }
}
