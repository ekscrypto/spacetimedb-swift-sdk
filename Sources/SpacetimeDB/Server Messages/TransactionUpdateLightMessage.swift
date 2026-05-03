//
//  TransactionUpdateLightMessage.swift
//  spacetimedb-swift-sdk
//

import Foundation
import BSATN

/// Server message tag 0x02 — a transaction-update variant carrying only the
/// `DatabaseUpdate` (table-row diffs), without the reducer call info, status,
/// timestamp, energy, or caller identity carried by full `TransactionUpdate`.
///
/// Servers send this form in light-mode subscriptions where the client has
/// opted out of receiving reducer event metadata.
public struct TransactionUpdateLightMessage: Sendable {
    public let requestId: UInt32
    public let update: DatabaseUpdate

    init(reader: BSATNReader) throws {
        requestId = try reader.read()
        update = try DatabaseUpdate(reader: reader)
        debugLog(">>> TransactionUpdateLightMessage: requestId=\(requestId), tables=\(update.tableUpdates.count)")
    }
}
