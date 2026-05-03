//
//  ReducerResultMessage.swift
//  spacetimedb-swift-sdk
//
//  v2 ServerMessage tag 0x06 — response to a CallReducer.
//  Wire: request_id (u32) + timestamp (i64 ns since epoch) + result: ReducerOutcome.
//
//  ReducerOutcome (sum):
//    0 -> Ok(ReducerOk { ret_value: bytes, transaction_update: TransactionUpdate })
//    1 -> OkEmpty           (no payload — implicit empty ret_value + tx_update)
//    2 -> Err(bytes)        — BSATN-encoded value of the reducer's error type
//    3 -> InternalError(s)  — host panic or unexpected failure
//
//  v1 collapsed self- and other-caused transactions into a single
//  TransactionUpdate; v2 routes the self-caused ones through here so the
//  caller can correlate via request_id and receive the reducer's return
//  value (which v1 had no path for).
//

import Foundation
import BSATN

public struct ReducerResultMessage: Sendable {
    public let requestId: UInt32
    public let timestampNanos: Int64
    public let outcome: ReducerOutcome

    init(reader: BSATNReader) throws {
        self.requestId = try reader.read()
        self.timestampNanos = try reader.read()
        self.outcome = try ReducerOutcome(reader: reader)
        debugLog(">>> ReducerResult: requestId=\(requestId), outcome=\(outcome.kind)")
    }
}

public enum ReducerOutcome: Sendable {
    /// Reducer committed and returned a value plus row diffs.
    case ok(returnValue: Data, transactionUpdate: TransactionUpdate)
    /// Reducer committed with empty return value and no row diffs.
    /// (Wire-level optimization that saves 8 bytes vs sending two empty `Box`es.)
    case okEmpty
    /// Reducer threw a typed error. Payload is BSATN-encoded according to
    /// the reducer's declared error type.
    case error(Data)
    /// Reducer panicked, returned an unstructured error, or otherwise
    /// failed inside the host. The string is diagnostic-only and should
    /// not be parsed.
    case internalError(String)

    init(reader: BSATNReader) throws {
        let tag: UInt8 = try reader.read()
        switch tag {
        case 0:
            let returnValueLen: UInt32 = try reader.read()
            let returnValue = Data(try reader.readBytes(Int(returnValueLen)))
            let txUpdate = try TransactionUpdate(reader: reader)
            self = .ok(returnValue: returnValue, transactionUpdate: txUpdate)
        case 1:
            self = .okEmpty
        case 2:
            let errLen: UInt32 = try reader.read()
            let errBytes = Data(try reader.readBytes(Int(errLen)))
            self = .error(errBytes)
        case 3:
            self = .internalError(try reader.readString())
        default:
            throw BSATNError.unsupportedTag(tag)
        }
    }

    var kind: String {
        switch self {
        case .ok: return "ok"
        case .okEmpty: return "okEmpty"
        case .error: return "error"
        case .internalError: return "internalError"
        }
    }
}
