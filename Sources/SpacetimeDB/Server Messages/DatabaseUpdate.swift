//
//  DatabaseUpdate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN

public struct DatabaseUpdate: Sendable {
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
                debugLog(">>> Warning: Expected product for TableUpdate, got: \(candidate)")
                continue
            }
            do {
                let update = try TableUpdate(modelValues: tableUpdateValues)
                updates.append(update)
            } catch {
                debugLog(">>> Error parsing TableUpdate: \(error)")
            }
        }
        self.tableUpdates = updates
    }

    // Alternative init that reads directly from BSATNReader
    init(reader: BSATNReader) throws {
        // Read array of TableUpdate
        debugLog(">>>   About to read table count at offset: \(reader.currentOffset)")
        let tableCount: UInt32 = try reader.read()
        debugLog(">>> DatabaseUpdate: \(tableCount) tables")

        var updates: [TableUpdate] = []
        for i in 0..<tableCount {
            debugLog(">>> Reading table \(i)...")
            let tableUpdate = try TableUpdate(reader: reader)
            updates.append(tableUpdate)
        }

        self.tableUpdates = updates
    }
}
