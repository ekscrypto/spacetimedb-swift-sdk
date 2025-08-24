//
//  MessageRow.swift
//  quickstart-chat
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN
import spacetimedb_swift_sdk

/// Represents a message row from the message table
struct MessageRow {
    let sender: UInt256 // UInt256 identity
    let text: String
    let sentAt: UInt64 // timestamp
    
    struct Model: ProductModel {
        var definition: [AlgebraicValueType] { [
            .uint256, // sender identity
            .string,  // message text
            .uint64   // timestamp
        ]}
    }
    
    init(modelValues: [AlgebraicValue]) throws {
        let model = Model()
        guard modelValues.count == model.definition.count,
              case .uint256(let sender) = modelValues[0],
              case .string(let text) = modelValues[1],
              case .uint64(let sentAt) = modelValues[2]
        else {
            throw BSATNError.invalidStructure("Invalid MessageRow structure")
        }
        
        self.sender = sender
        self.text = text
        self.sentAt = sentAt
    }
}

struct MessageRowDecoder: TableRowDecoder {
    var model: ProductModel { MessageRow.Model() }
    func decode(modelValues: [AlgebraicValue]) throws -> Any { 
        try MessageRow(modelValues: modelValues) 
    }
}