//
//  SpacetimeDBClient+callReducer.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-24.
//

import Foundation
import BSATN

extension SpacetimeDBClient {
    
    /// Call a reducer on the SpacetimeDB server
    /// - Parameter reducer: The reducer to call
    /// - Returns: The request ID used for this call
    /// - Throws: An error if the reducer call fails
    @discardableResult
    public func callReducer(_ reducer: Reducer) async throws -> UInt32 {
        let requestId = UInt32.random(in: 1...UInt32.max)
        
        let request = try CallReducerRequest(reducer: reducer, requestId: requestId)
        let encodedRequest = try request.encode()
        
        // The request already includes the message type tag
        let message = encodedRequest
        
        // Send the message
        guard let webSocketTask = webSocketTask else {
            throw Errors.disconnected
        }
        
        try await webSocketTask.send(URLSessionWebSocketTask.Message.data(message))
        
        print("📤 Called reducer '\(reducer.name)' with request ID: \(requestId)")
        
        return requestId
    }
    
    /// Call a reducer with a single string argument
    /// - Parameters:
    ///   - name: The name of the reducer
    ///   - argument: The string argument to pass
    /// - Returns: The request ID used for this call
    /// - Throws: An error if the reducer call fails
    @discardableResult
    public func callReducer(name: String, argument: String) async throws -> UInt32 {
        let reducer = StringReducer(name: name, argument: argument)
        return try await callReducer(reducer)
    }
    
    /// Call a reducer with no arguments
    /// - Parameters:
    ///   - name: The name of the reducer
    /// - Returns: The request ID used for this call
    /// - Throws: An error if the reducer call fails
    @discardableResult
    public func callReducer(name: String) async throws -> UInt32 {
        let reducer = VoidReducer(name: name)
        return try await callReducer(reducer)
    }
    
    /// Call a reducer with raw BSATN-encoded arguments
    /// - Parameters:
    ///   - name: The name of the reducer
    ///   - encodedArguments: The BSATN-encoded arguments
    /// - Returns: The request ID used for this call
    /// - Throws: An error if the reducer call fails
    @discardableResult
    public func callReducer(name: String, encodedArguments: Data) async throws -> UInt32 {
        let reducer = RawReducer(name: name, encodedArguments: encodedArguments)
        return try await callReducer(reducer)
    }
}