//
//  UnsubscribeMultiAppliedMessage.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-28.
//

import Foundation
import BSATN

public struct UnsubscribeMultiAppliedMessage: Sendable {
    public let requestId: UInt32
    public let totalHostExecutionDurationMicros: UInt64
    public let queryId: UInt32
    public let update: DatabaseUpdate
    
    init(reader: BSATNReader) throws {
        requestId = try reader.read()
        totalHostExecutionDurationMicros = try reader.read()
        queryId = try reader.read()
        update = try DatabaseUpdate(reader: reader)
        debugLog(">>> UnsubscribeMultiAppliedMessage: requestId=\(requestId), queryId=\(queryId)")
    }
}

public struct UnsubscribeAppliedMessage: Sendable {
    public let requestId: UInt32
    public let totalHostExecutionDurationMicros: UInt64
    public let queryId: UInt32
    public let update: DatabaseUpdate
    
    init(reader: BSATNReader) throws {
        requestId = try reader.read()
        totalHostExecutionDurationMicros = try reader.read()
        queryId = try reader.read()
        update = try DatabaseUpdate(reader: reader)
        debugLog(">>> UnsubscribeAppliedMessage: requestId=\(requestId), queryId=\(queryId)")
    }
}