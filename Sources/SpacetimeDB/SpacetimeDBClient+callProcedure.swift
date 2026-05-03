//
//  SpacetimeDBClient+callProcedure.swift
//  spacetimedb-swift-sdk
//
//  v2 Procedures — non-transactional read-only RPCs. Distinct from
//  reducers in that they don't commit a transaction or produce a
//  TransactionUpdate; the response is just a return value (or error).
//

import Foundation
import BSATN

public enum ProcedureCallError: Error {
    /// Host-level failure (unknown procedure, type error, panic, etc.).
    /// User-level errors are reported inside the returned `Data` payload
    /// (which can encode any user-defined Result/Option type).
    case internalError(String)
}

extension SpacetimeDBClient {
    /// Invoke a procedure with typed arguments and return value.
    /// Mirrors `callReducer(_:)` for the `Reducer` family.
    @discardableResult
    public func callProcedure<P: Procedure>(_ procedure: P) async throws -> P.ReturnValue {
        let writer = BSATNWriter()
        try procedure.encodeArguments(writer: writer)
        let raw = try await callProcedure(name: procedure.name, arguments: writer.finalize())
        return try procedure.decodeReturnValue(raw)
    }

    /// Invoke a procedure and suspend until the server responds.
    /// On `.returned`, the BSATN-encoded payload is returned to the
    /// caller; on `.internalError`, throws `ProcedureCallError`.
    @discardableResult
    public func callProcedure(name: String, arguments: Data = Data()) async throws -> Data {
        guard let webSocketTask else { throw Errors.disconnected }
        let requestId = nextRequestId
        let request = CallProcedureRequest(
            procedure: name,
            arguments: arguments,
            requestId: requestId
        )
        let payload = try request.encode()

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingProcedureCalls[requestId] = PendingProcedureCall(
                procedureName: name,
                continuation: continuation
            )
            Task {
                do {
                    try await webSocketTask.send(.data(payload))
                } catch {
                    if self.pendingProcedureCalls.removeValue(forKey: requestId) != nil {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: Resolution helpers (called from the receive loop)

    internal func resolvePendingProcedure(requestId: UInt32, status: ProcedureStatus) {
        guard let pending = pendingProcedureCalls.removeValue(forKey: requestId) else { return }
        switch status {
        case .returned(let bytes):
            pending.continuation.resume(returning: bytes)
        case .internalError(let message):
            pending.continuation.resume(throwing: ProcedureCallError.internalError(message))
        }
    }

    internal func procedureName(forRequestId requestId: UInt32) -> String? {
        pendingProcedureCalls[requestId]?.procedureName
    }
}
