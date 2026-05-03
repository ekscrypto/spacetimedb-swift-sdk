//
//  UnsubscribeAppliedMessage.swift
//  spacetimedb-swift-sdk
//
//  v2 ServerMessage tag 0x02.
//  Wire: request_id (u32) + query_set_id (u32) + rows: Option<QueryRows>.
//
//  `rows` is populated only if the original Unsubscribe message had the
//  SendDroppedRows flag set; otherwise the dropped rows are not echoed.
//

import Foundation
import BSATN

public struct UnsubscribeAppliedMessage: Sendable {
    public let requestId: UInt32
    public let querySetId: QuerySetId
    public let droppedRows: QueryRows?

    init(reader: BSATNReader) throws {
        self.requestId = try reader.read()
        self.querySetId = try QuerySetId(reader: reader)
        let optionTag: UInt8 = try reader.read()
        switch optionTag {
        case 0:
            self.droppedRows = try QueryRows(reader: reader)
        case 1:
            self.droppedRows = nil
        default:
            throw BSATNError.unsupportedTag(optionTag)
        }
        debugLog(">>> UnsubscribeApplied: requestId=\(requestId), querySetId=\(querySetId.id), droppedRows=\(droppedRows?.tables.count.description ?? "nil")")
    }
}
