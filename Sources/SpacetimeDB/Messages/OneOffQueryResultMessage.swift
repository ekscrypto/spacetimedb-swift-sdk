//
//  OneOffQueryResultMessage.swift
//  spacetimedb-swift-sdk
//
//  v2 ServerMessage tag 0x05.
//  Wire: request_id (u32) + result: Result<QueryRows, string>
//        (BSATN sum tag: 0 = Ok(QueryRows), 1 = Err(string)).
//

import Foundation
import BSATN

public struct OneOffQueryResultMessage: Sendable {
    public let requestId: UInt32
    public let result: OneOffResult

    /// Wire-level Result<QueryRows, String>. Modeled as a custom enum
    /// instead of Swift's `Result<_, _>` because the BSATN error variant
    /// is a plain string, not a Swift `Error`.
    public enum OneOffResult: Sendable {
        case ok(QueryRows)
        case error(String)
    }

    init(reader: BSATNReader) throws {
        self.requestId = try reader.read()
        let tag: UInt8 = try reader.read()
        switch tag {
        case 0:
            self.result = .ok(try QueryRows(reader: reader))
        case 1:
            self.result = .error(try reader.readString())
        default:
            throw BSATNError.unsupportedTag(tag)
        }
        switch result {
        case .ok(let rows):
            debugLog(">>> OneOffQueryResult: requestId=\(requestId), tables=\(rows.tables.count)")
        case .error(let error):
            debugLog(">>> OneOffQueryResult: requestId=\(requestId), error=\(error)")
        }
    }
}
