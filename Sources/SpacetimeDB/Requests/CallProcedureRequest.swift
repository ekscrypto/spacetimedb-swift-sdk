//
//  CallProcedureRequest.swift
//  spacetimedb-swift-sdk
//
//  v2 CallProcedure message — see crates/client-api-messages/src/websocket/v2.rs
//  Wire: tag (u8=0x04) + request_id (u32) + flags (u8) + procedure (string) + args (bytes)
//

import Foundation
import BSATN

public struct CallProcedureRequest {
    public let requestId: UInt32
    public let flags: CallProcedureFlags
    public let procedure: String
    public let arguments: Data

    public init(
        procedure: String,
        arguments: Data,
        requestId: UInt32 = UInt32.random(in: 1...UInt32.max),
        flags: CallProcedureFlags = .default
    ) {
        self.requestId = requestId
        self.flags = flags
        self.procedure = procedure
        self.arguments = arguments
    }

    public func encode() throws -> Data {
        let writer = BSATNWriter()
        writer.write(Tags.ClientMessage.callProcedure.rawValue)
        writer.write(requestId)
        flags.encode(to: writer)
        try writer.write(procedure)
        writer.write(UInt32(arguments.count))
        writer.writeBytes(arguments)
        return writer.finalize()
    }
}
