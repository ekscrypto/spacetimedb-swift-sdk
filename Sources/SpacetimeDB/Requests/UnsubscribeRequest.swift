//
//  UnsubscribeRequest.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-28.
//

import Foundation
import BSATN

struct UnsubscribeMultiRequest {
    let requestId: UInt32
    let queryId: UInt32

    func encode() throws -> Data {
        let writer = BSATNWriter()
        try writer.writeAlgebraicValue(.uint32(requestId))
        try writer.writeAlgebraicValue(.uint32(queryId))
        return writer.finalize()
    }
}

struct UnsubscribeRequest {
    let requestId: UInt32
    let queryId: UInt32

    init(requestId: UInt32, queryId: UInt32) {
        self.requestId = requestId
        self.queryId = queryId
    }

    func encode() throws -> Data {
        let writer = BSATNWriter()
        writer.write(requestId)
        writer.write(queryId)
        return writer.finalize()
    }
}