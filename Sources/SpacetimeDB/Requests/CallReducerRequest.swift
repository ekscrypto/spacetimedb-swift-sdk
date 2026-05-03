//
//  CallReducerRequest.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-24.
//

import Foundation
import BSATN

/// Request to call a reducer on the SpacetimeDB server
public struct CallReducerRequest {
    public let reducer: String
    public let arguments: Data
    public let requestId: UInt32
    public let flags: UInt8

    public init(reducer: String, arguments: Data, requestId: UInt32 = UInt32.random(in: 1...UInt32.max), flags: UInt8 = 0) {
        self.reducer = reducer
        self.arguments = arguments
        self.requestId = requestId
        self.flags = flags
    }

    public init(reducer: Reducer, requestId: UInt32 = UInt32.random(in: 1...UInt32.max), flags: UInt8 = 0) throws {
        self.reducer = reducer.name

        // Encode the arguments
        let writer = BSATNWriter()
        try reducer.encodeArguments(writer: writer)
        self.arguments = writer.finalize()

        self.requestId = requestId
        self.flags = flags
    }

    /// Encode the CallReducer request to BSATN format
    /// Field order from TypeScript SDK: reducer (string), args (array of u8), requestId (u32), flags (u8)
    public func encode() throws -> Data {
        let writer = BSATNWriter()

        // Include message type tag like SubscribeMulti does
        try writer.writeAlgebraicValue(.uint8(Tags.ClientMessage.callReducer.rawValue))

        // 1. Reducer name as BSATN string
        try writer.write(reducer)

        // 2. Arguments as array of u8
        writer.write(UInt32(arguments.count))
        writer.writeBytes(arguments)

        // 3. Request ID
        writer.write(requestId)

        // 4. Flags
        writer.write(flags)

        return writer.finalize()
    }
}