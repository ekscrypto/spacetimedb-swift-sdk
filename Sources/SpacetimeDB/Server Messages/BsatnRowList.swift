//
//  BsatnRowList.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN

/// Represents a list of BSATN-encoded rows
public struct BsatnRowList {
    public let rows: [Data]

    struct Model: ArrayModel {
        var definition: AlgebraicValueType {
            .array(ByteArrayModel())
        }
    }

    struct ByteArrayModel: ArrayModel {
        var definition: AlgebraicValueType {
            .uint8
        }
    }

    init(from algebraicValue: AlgebraicValue) throws {
        guard case .array(let arrayValues) = algebraicValue else {
            throw BSATNError.invalidStructure("Expected array for BsatnRowList")
        }

        debugLog(">>> BsatnRowList: parsing \(arrayValues.count) rows")

        var rows: [Data] = []
        for (index, value) in arrayValues.enumerated() {
            guard case .array(let byteValues) = value else {
                throw BSATNError.invalidStructure("Expected array of bytes for row")
            }

            var rowData = Data()
            for byteValue in byteValues {
                guard case .uint8(let byte) = byteValue else {
                    throw BSATNError.invalidStructure("Expected uint8 for byte value")
                }
                rowData.append(byte)
            }

            // Debug: show first few bytes of each row
            if rowData.count > 0 {
                let preview = rowData.prefix(min(50, rowData.count))
                let hex = preview.map { String(format: "%02X", $0) }.joined(separator: " ")
                debugLog(">>>   Row \(index): \(rowData.count) bytes - \(hex)")

                // Check for readable text
                let ascii = preview.compactMap { byte -> Character? in
                    if byte >= 32 && byte <= 126 {
                        return Character(UnicodeScalar(byte))
                    }
                    return nil
                }
                if !ascii.isEmpty {
                    debugLog(">>>     ASCII: \(String(ascii))")
                }
            }

            rows.append(rowData)
        }

        self.rows = rows
    }

    init(rows: [Data] = []) {
        self.rows = rows
    }
}