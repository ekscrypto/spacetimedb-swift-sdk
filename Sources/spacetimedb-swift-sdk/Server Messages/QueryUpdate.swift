//
//  QueryUpdate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN

/// Represents a query update containing deletes and inserts
struct QueryUpdate {
    let deletes: BsatnRowList
    let inserts: BsatnRowList
    
    struct Model: ProductModel {
        var definition: [AlgebraicValueType] { [
            .array(BsatnRowList.Model()),
            .array(BsatnRowList.Model())
        ]}
    }
    
    init(modelValues: [AlgebraicValue]) throws {
        let model = Model()
        print("Will be decoding QueryUpdate from values: \(modelValues)")
        guard modelValues.count == model.definition.count else {
            throw SpacetimeDBErrors.invalidDefinition(model)
        }
        
        self.deletes = try BsatnRowList(from: modelValues[0])
        self.inserts = try BsatnRowList(from: modelValues[1])
    }
    
    init(deletes: BsatnRowList = BsatnRowList(), inserts: BsatnRowList = BsatnRowList()) {
        self.deletes = deletes
        self.inserts = inserts
    }
}