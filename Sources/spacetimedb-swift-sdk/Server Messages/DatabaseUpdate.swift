//
//  DatabaseUpdate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN

public struct DatabaseUpdate {
    public let tableUpdates: [TableUpdate]

    struct Model: ArrayModel {
        let definition: AlgebraicValueType = .product(TableUpdate.Model())
    }
    
    public init(tableUpdates: [TableUpdate]) {
        self.tableUpdates = tableUpdates
    }

    init(modelValues: [AlgebraicValue]) throws {
        var updates: [TableUpdate] = []
        for candidate in modelValues {
            guard case .product(let tableUpdateValues) = candidate else {
                print(">>> Warning: Expected product for TableUpdate, got: \(candidate)")
                continue
            }
            do {
                let update = try TableUpdate(modelValues: tableUpdateValues)
                updates.append(update)
            } catch {
                print(">>> Error parsing TableUpdate: \(error)")
            }
        }
        self.tableUpdates = updates
    }
    
    // Alternative init that reads directly from BSATNReader
    init(reader: BSATNReader) throws {
        // Read array of TableUpdate
        print(">>>   About to read table count at offset: \(reader.currentOffset)")
        let tableCount: UInt32 = try reader.read()
        print(">>> DatabaseUpdate: \(tableCount) tables")
        
        var updates: [TableUpdate] = []
        for i in 0..<tableCount {
            print(">>> Reading table \(i)...")
            let tableUpdate = try TableUpdate(reader: reader)
            updates.append(tableUpdate)
        }
        
        self.tableUpdates = updates
    }
}
