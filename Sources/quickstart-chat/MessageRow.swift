//
//  MessageRow.swift
//  quickstart-chat
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN
import SpacetimeDB

/// Represents a message row from the message table
struct MessageRow {
    let sender: UInt256 // UInt256 identity
    let sent: UInt64    // timestamp
    let text: String    // message text

    struct Model: ProductModel {
        var definition: [AlgebraicValueType] { [
            .uint256, // sender identity
            .uint64,  // timestamp (sent)
            .string   // message text
        ]}
    }

    init(modelValues: [AlgebraicValue]) throws {
        let model = Model()
        guard modelValues.count == model.definition.count,
              case .uint256(let sender) = modelValues[0],
              case .uint64(let sent) = modelValues[1],
              case .string(let text) = modelValues[2]
        else {
            throw BSATNError.invalidStructure("Invalid MessageRow structure")
        }

        self.sender = sender
        self.sent = sent
        self.text = text
    }
}

struct MessageRowDecoder: TableRowDecoder {
    var model: ProductModel { MessageRow.Model() }
    func decode(modelValues: [AlgebraicValue]) throws -> Any {
        try MessageRow(modelValues: modelValues)
    }
}