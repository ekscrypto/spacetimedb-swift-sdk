//
//  SubscriptionErrorMessage.swift
//  spacetimedb-swift-sdk
//
//  v2 ServerMessage tag 0x03.
//  Wire: request_id (Option<u32>) + query_set_id (u32) + error (string).
//
//  request_id is None when the failure occurred mid-subscription (during
//  recompilation or incremental evaluation), Some when it's the response
//  to a client-issued Subscribe.
//

import Foundation
import BSATN

public struct SubscriptionErrorMessage: Sendable {
    public let requestId: UInt32?
    public let querySetId: QuerySetId
    public let error: String

    init(reader: BSATNReader) throws {
        self.requestId = try reader.readOptional { try reader.read() }
        self.querySetId = try QuerySetId(reader: reader)
        self.error = try reader.readString()
        debugLog(">>> SubscriptionError: requestId=\(requestId.map(String.init) ?? "nil"), querySetId=\(querySetId.id), error=\(error)")
    }
}
