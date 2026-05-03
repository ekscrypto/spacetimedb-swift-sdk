//
//  CallReducerRequest.swift
//  spacetimedb-swift-sdk
//
//  v2 CallReducer message — see crates/client-api-messages/src/websocket/v2.rs
//  Wire: tag (u8=0x03) + request_id (u32) + flags (u8) + reducer (string) + args (bytes)
//

import Foundation
import BSATN

public struct CallReducerRequest {
    public let requestId: UInt32
    public let flags: CallReducerFlags
    public let reducer: String
    public let arguments: Data

    public init(
        reducer: String,
        arguments: Data,
        requestId: UInt32 = UInt32.random(in: 1...UInt32.max),
        flags: CallReducerFlags = .default
    ) {
        self.requestId = requestId
        self.flags = flags
        self.reducer = reducer
        self.arguments = arguments
    }

    public init(
        reducer: Reducer,
        requestId: UInt32 = UInt32.random(in: 1...UInt32.max),
        flags: CallReducerFlags = .default
    ) throws {
        let writer = BSATNWriter()
        try reducer.encodeArguments(writer: writer)
        self.init(
            reducer: reducer.name,
            arguments: writer.finalize(),
            requestId: requestId,
            flags: flags
        )
    }

    public func encode() throws -> Data {
        let writer = BSATNWriter()
        writer.write(Tags.ClientMessage.callReducer.rawValue)
        writer.write(requestId)
        flags.encode(to: writer)
        try writer.write(reducer)
        writer.write(UInt32(arguments.count))
        writer.writeBytes(arguments)
        return writer.finalize()
    }
}
