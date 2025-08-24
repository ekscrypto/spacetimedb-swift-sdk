//
//  SubscribeMultiApplied.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN

struct SubscribeMultiApplied {
    /// the requestId matching the subscription request
    let requestId: UInt32

    /// total host execution duration in microseconds
    let executionDuration: UInt64

    /// The queryId specified in the subscribe multi request
    let queryId: UInt32

    let update: DatabaseUpdate

    struct Model: ProductModel {
        var definition: [AlgebraicValueType] { [
            .uint32, // requestId
            .uint64, // total host execution duration
            .uint32, // queryId
            .array(DatabaseUpdate.Model())
        ]}
    }

    init(modelValues: [AlgebraicValue]) throws {
        let model = Model()
        guard modelValues.count == model.definition.count,
              case .uint32(let requestId) = modelValues[0],
              case .uint64(let executionDuration) = modelValues[1],
              case .uint32(let queryId) = modelValues[2],
              case .array(let updateValues) = modelValues[3]
        else {
            throw SpacetimeDBErrors.invalidDefinition(model)
        }
        self.requestId = requestId
        self.executionDuration = executionDuration
        self.queryId = queryId
        self.update = try DatabaseUpdate(modelValues: updateValues)
    }
    
    // Alternative init that reads directly from BSATNReader
    init(reader: BSATNReader) throws {
        self.requestId = try reader.read()
        self.executionDuration = try reader.read()
        self.queryId = try reader.read()
        self.update = try DatabaseUpdate(reader: reader)
        
        print(">>> SubscribeMultiApplied: requestId=\(requestId), queryId=\(queryId), hostExec=\(executionDuration)μs, tables=\(update.tableUpdates.count)")
    }
}
