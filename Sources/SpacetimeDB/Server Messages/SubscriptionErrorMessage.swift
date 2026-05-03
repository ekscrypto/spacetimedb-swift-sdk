//
//  SubscriptionErrorMessage.swift
//  spacetimedb-swift-sdk
//

import Foundation
import BSATN

/// Server message tag 0x07 — sent when a subscription lifecycle event fails.
///
/// `requestId` and `queryId` are absent when the error is the result of a
/// transaction update rather than a client-issued Subscribe / Unsubscribe.
/// `tableId`, when present, scopes the failure to that table only;
/// when absent, the entire subscription is dropped.
public struct SubscriptionErrorMessage: Sendable {
    public let totalHostExecutionDurationMicros: UInt64
    public let requestId: UInt32?
    public let queryId: UInt32?
    public let tableId: UInt32?
    public let error: String

    init(reader: BSATNReader) throws {
        totalHostExecutionDurationMicros = try reader.read()
        requestId = try reader.readOptional { try reader.read() }
        queryId = try reader.readOptional { try reader.read() }
        tableId = try reader.readOptional { try reader.read() }
        error = try reader.readString()
        debugLog(">>> SubscriptionErrorMessage: queryId=\(queryId.map(String.init) ?? "nil"), tableId=\(tableId.map(String.init) ?? "nil"), error=\(error)")
    }
}
