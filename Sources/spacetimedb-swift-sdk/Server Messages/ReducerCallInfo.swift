//
//  ReducerCallInfo.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-24.
//

import Foundation
import BSATN

/// Information about a reducer call
public struct ReducerCallInfo {
    public let reducerName: String
    public let reducerId: UInt32
    public let args: Data
    public let requestId: UInt32
    
    init(reader: BSATNReader) throws {
        print(">>> Reading ReducerCallInfo")
        self.reducerName = try reader.readString()
        print(">>>   Reducer name: \(self.reducerName)")
        self.reducerId = try reader.read()
        print(">>>   Reducer ID: \(self.reducerId)")
        let argsLength: UInt32 = try reader.read()
        print(">>>   Args length: \(argsLength)")
        self.args = Data(try reader.readBytes(Int(argsLength)))
        print(">>>   Args read: \(self.args.count) bytes")
        self.requestId = try reader.read()
        print(">>>   Request ID: \(self.requestId)")
    }
}