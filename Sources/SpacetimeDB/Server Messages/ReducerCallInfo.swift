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
        debugLog(">>> Reading ReducerCallInfo")
        self.reducerName = try reader.readString()
        debugLog(">>>   Reducer name: \(self.reducerName)")
        self.reducerId = try reader.read()
        debugLog(">>>   Reducer ID: \(self.reducerId)")
        let argsLength: UInt32 = try reader.read()
        debugLog(">>>   Args length: \(argsLength)")
        self.args = Data(try reader.readBytes(Int(argsLength)))
        debugLog(">>>   Args read: \(self.args.count) bytes")
        self.requestId = try reader.read()
        debugLog(">>>   Request ID: \(self.requestId)")
    }
}