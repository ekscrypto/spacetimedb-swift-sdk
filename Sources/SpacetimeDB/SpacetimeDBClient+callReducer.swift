//
//  SpacetimeDBClient+callReducer.swift
//  spacetimedb-swift-sdk
//

import Foundation
import BSATN

/// Successful reducer invocation (`ReducerOutcome.ok` or `.okEmpty`).
public struct ReducerSuccess: Sendable {
    /// BSATN-encoded reducer return value. Empty for `.okEmpty`.
    public let returnValue: Data
    /// Server-side timestamp the reducer started executing.
    public let timestamp: Date
    /// Row diffs caused by this reducer's transaction.
    public let transactionUpdate: TransactionUpdate
}

public enum ReducerCallError: Error {
    /// Typed error returned by the reducer; payload is BSATN-encoded
    /// according to the reducer's declared error type.
    case executionError(Data)
    /// Host-level failure (panic, type error, internal SpacetimeDB error).
    case internalError(String)
}

extension SpacetimeDBClient {
    /// Invoke a reducer and suspend until the server responds.
    /// Returns the reducer's success payload on `.ok` / `.okEmpty`;
    /// throws `ReducerCallError` on `.error` / `.internalError`.
    @discardableResult
    public func callReducer(_ reducer: Reducer) async throws -> ReducerSuccess {
        let writer = BSATNWriter()
        try reducer.encodeArguments(writer: writer)
        return try await callReducer(name: reducer.name, encodedArguments: writer.finalize())
    }

    /// Convenience for reducers that take a single `String` argument.
    @discardableResult
    public func callReducer(name: String, argument: String) async throws -> ReducerSuccess {
        try await callReducer(StringReducer(name: name, argument: argument))
    }

    /// Convenience for reducers that take no arguments.
    @discardableResult
    public func callReducer(name: String) async throws -> ReducerSuccess {
        try await callReducer(VoidReducer(name: name))
    }

    /// Invoke a reducer with raw BSATN-encoded arguments.
    @discardableResult
    public func callReducer(name: String, encodedArguments: Data) async throws -> ReducerSuccess {
        guard let webSocketTask else { throw Errors.disconnected }
        let requestId = nextRequestId
        let request = CallReducerRequest(
            reducer: name,
            arguments: encodedArguments,
            requestId: requestId
        )
        let payload = try request.encode()

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingReducerCalls[requestId] = PendingReducerCall(
                reducerName: name,
                continuation: continuation
            )
            Task {
                do {
                    try await webSocketTask.send(.data(payload))
                } catch {
                    if self.pendingReducerCalls.removeValue(forKey: requestId) != nil {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: Resolution helpers (called from the receive loop)

    internal func resolvePendingReducer(requestId: UInt32, timestampNanos: Int64, outcome: ReducerOutcome) {
        guard let pending = pendingReducerCalls.removeValue(forKey: requestId) else { return }
        let timestamp = Date(timeIntervalSince1970: TimeInterval(timestampNanos) / 1_000_000_000)
        switch outcome {
        case .ok(let returnValue, let txUpdate):
            pending.continuation.resume(returning: ReducerSuccess(
                returnValue: returnValue,
                timestamp: timestamp,
                transactionUpdate: txUpdate
            ))
        case .okEmpty:
            pending.continuation.resume(returning: ReducerSuccess(
                returnValue: Data(),
                timestamp: timestamp,
                transactionUpdate: TransactionUpdate(querySets: [])
            ))
        case .error(let bytes):
            pending.continuation.resume(throwing: ReducerCallError.executionError(bytes))
        case .internalError(let message):
            pending.continuation.resume(throwing: ReducerCallError.internalError(message))
        }
    }

    internal func reducerName(forRequestId requestId: UInt32) -> String? {
        pendingReducerCalls[requestId]?.reducerName
    }
}
