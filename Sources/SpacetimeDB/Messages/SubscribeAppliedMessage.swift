//
//  SubscribeAppliedMessage.swift
//  spacetimedb-swift-sdk
//
//  v2 ServerMessage tag 0x01.
//  Wire: request_id (u32) + query_set_id (u32) + rows: QueryRows.
//

import Foundation
import BSATN

public struct SubscribeAppliedMessage: Sendable {
    public let requestId: UInt32
    public let querySetId: QuerySetId
    public let rows: QueryRows

    init(reader: BSATNReader) throws {
        self.requestId = try reader.read()
        self.querySetId = try QuerySetId(reader: reader)
        self.rows = try QueryRows(reader: reader)
        debugLog(">>> SubscribeApplied: requestId=\(requestId), querySetId=\(querySetId.id), tables=\(rows.tables.count)")
    }
}
