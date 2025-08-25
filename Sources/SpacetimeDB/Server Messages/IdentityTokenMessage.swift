//
//  IdentityTokenMessage.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation
import BSATN

struct IdentityTokenMessage {
    let identity: UInt256
    let token: String
    let connectionId: BSATN.UInt128

    struct Model: ProductModel {
        var definition: [AlgebraicValueType] { [
            .uint256, // identity
            .string, // token
            .uint128 // connection_id
        ]}
    }

    init(modelValues: [AlgebraicValue]) throws {
        let model = Model()
        guard modelValues.count == model.definition.count,
              case .uint256(let identity) = modelValues[0],
              case .string(let token) = modelValues[1],
              case .uint128(let connectionId) = modelValues[2]
        else {
            throw SpacetimeDBErrors.invalidDefinition(model)
        }
        self.identity = identity
        self.token = token
        self.connectionId = connectionId
    }
}
