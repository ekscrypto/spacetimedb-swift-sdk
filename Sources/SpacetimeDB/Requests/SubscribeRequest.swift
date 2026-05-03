//
//  SubscribeRequest.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-28.
//

import Foundation
import BSATN

struct SubscribeRequest {
    let queries: [String]
    let requestId: UInt32

    init(queries: [String], requestId: UInt32) {
        self.queries = queries
        self.requestId = requestId
    }

    func encode() throws -> Data {
        let writer = BSATNWriter()
        
        // Write queries count and query strings (same as SubscribeMulti)
        writer.write(UInt32(queries.count))
        for query in queries {
            try writer.write(query)
        }
        
        // Write request ID
        writer.write(requestId)
        
        return writer.finalize()
    }
}