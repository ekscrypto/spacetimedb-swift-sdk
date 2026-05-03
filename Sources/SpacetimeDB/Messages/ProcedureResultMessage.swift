//
//  ProcedureResultMessage.swift
//  spacetimedb-swift-sdk
//
//  v2 ServerMessage tag 0x07 — response to a CallProcedure.
//  Wire: status: ProcedureStatus + timestamp (i64) +
//        total_host_execution_duration (i64) + request_id (u32).
//
//  ProcedureStatus (sum):
//    0 -> Returned(bytes)   — return value (any user type — could be Result/Option;
//                             user-level error handling lives inside this payload)
//    1 -> InternalError(s)  — host-level failure (type error, unknown procedure, etc.)
//

import Foundation
import BSATN

public struct ProcedureResultMessage: Sendable {
    public let status: ProcedureStatus
    public let timestampNanos: Int64
    public let totalHostExecutionDurationNanos: Int64
    public let requestId: UInt32

    init(reader: BSATNReader) throws {
        self.status = try ProcedureStatus(reader: reader)
        self.timestampNanos = try reader.read()
        self.totalHostExecutionDurationNanos = try reader.read()
        self.requestId = try reader.read()
        debugLog(">>> ProcedureResult: requestId=\(requestId), status=\(status.kind)")
    }
}

public enum ProcedureStatus: Sendable {
    case returned(Data)
    case internalError(String)

    init(reader: BSATNReader) throws {
        let tag: UInt8 = try reader.read()
        switch tag {
        case 0:
            let len: UInt32 = try reader.read()
            self = .returned(Data(try reader.readBytes(Int(len))))
        case 1:
            self = .internalError(try reader.readString())
        default:
            throw BSATNError.unsupportedTag(tag)
        }
    }

    var kind: String {
        switch self {
        case .returned: return "returned"
        case .internalError: return "internalError"
        }
    }
}
