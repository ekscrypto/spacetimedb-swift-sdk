//
//  Reducer.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-24.
//

import Foundation
import BSATN

/// Protocol for defining reducers that can be called on SpacetimeDB
public protocol Reducer {
    /// The name of the reducer as defined on the server
    var name: String { get }

    /// Encode the reducer arguments to BSATN format
    func encodeArguments(writer: BSATNWriter) throws
}

/// A simple reducer with a single string argument
public struct StringReducer: Reducer {
    public let name: String
    public let argument: String

    public init(name: String, argument: String) {
        self.name = name
        self.argument = argument
    }

    public func encodeArguments(writer: BSATNWriter) throws {
        try writer.write(argument)
    }
}

/// A reducer with no arguments
public struct VoidReducer: Reducer {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    public func encodeArguments(writer: BSATNWriter) throws {
        // No arguments to encode
    }
}

/// Generic reducer that takes encoded BSATN data directly
public struct RawReducer: Reducer {
    public let name: String
    public let encodedArguments: Data

    public init(name: String, encodedArguments: Data) {
        self.name = name
        self.encodedArguments = encodedArguments
    }

    public func encodeArguments(writer: BSATNWriter) throws {
        writer.writeBytes(encodedArguments)
    }
}