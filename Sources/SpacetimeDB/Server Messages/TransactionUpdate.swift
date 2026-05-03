//
//  TransactionUpdate.swift
//  spacetimedb-swift-sdk
//
//  v2 ServerMessage tag 0x04.
//  Wire: query_sets: Box<[QuerySetUpdate]> (u32 count + entries).
//
//  Sent for transactions that affect this client's subscribed query sets
//  but were NOT initiated by this client. (Self-caused transactions arrive
//  via ReducerResult, which embeds its own TransactionUpdate.) The message
//  carries no reducer metadata — that information is intentionally omitted
//  because it is not relevant to other clients.
//

import Foundation
import BSATN

public struct TransactionUpdate: Sendable {
    public let querySets: [QuerySetUpdate]

    public init(querySets: [QuerySetUpdate]) {
        self.querySets = querySets
    }

    init(reader: BSATNReader) throws {
        let count: UInt32 = try reader.read()
        var sets: [QuerySetUpdate] = []
        sets.reserveCapacity(Int(count))
        for _ in 0..<count {
            sets.append(try QuerySetUpdate(reader: reader))
        }
        self.querySets = sets
        debugLog(">>> TransactionUpdate: \(sets.count) query sets")
    }
}
