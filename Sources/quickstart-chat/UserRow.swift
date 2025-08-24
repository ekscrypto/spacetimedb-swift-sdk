//
//  UserRow.swift
//  quickstart-chat
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN
import spacetimedb_swift_sdk

/// Represents a user row from the user table
struct UserRow {
    let identity: UInt256 // UInt256 identity
    let name: String?     // Optional name
    let online: Bool      // Online status
    
    struct Model: ProductModel {
        var definition: [AlgebraicValueType] { [
            .uint256,   // identity
            .option(.string),  // name (optional string)
            .bool       // online status
        ]}
    }
    
    init(modelValues: [AlgebraicValue]) throws {
        let model = Model()
        guard modelValues.count == model.definition.count,
              case .uint256(let identity) = modelValues[0]
        else {
            throw BSATNError.invalidStructure("Invalid UserRow structure")
        }
        
        self.identity = identity
        
        // Handle optional name (sum type: tag 0=Some, tag 1=None)
        switch modelValues[1] {
        case .sum(tag: 0, value: let data):
            // Some case - the data contains the string
            let reader = BSATNReader(data: data)
            let nameValue = try reader.readAlgebraicValue(as: .string)
            guard case .string(let name) = nameValue else {
                throw BSATNError.invalidStructure("Expected string for name")
            }
            self.name = name.isEmpty ? nil : name
        case .sum(tag: 1, value: _):
            // None case
            self.name = nil
        default:
            throw BSATNError.invalidStructure("Expected sum type for optional name field")
        }
        
        // Handle online status
        guard case .bool(let online) = modelValues[2] else {
            throw BSATNError.invalidStructure("Expected bool for online field")
        }
        self.online = online
    }
    
    /// Alternative init that reads directly from BSATNReader
    init(reader: BSATNReader) throws {
        // Read identity
        self.identity = try reader.read()
        
        // Read optional name using the new readOptional method
        self.name = try reader.readOptional {
            try reader.readString()
        }
        
        // Read online status
        self.online = try reader.read()
    }
}

struct UserRowDecoder: TableRowDecoder {
    var model: ProductModel { UserRow.Model() }
    func decode(modelValues: [AlgebraicValue]) throws -> Any { 
        try UserRow(modelValues: modelValues) 
    }
}