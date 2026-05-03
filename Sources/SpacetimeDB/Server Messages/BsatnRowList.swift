//
//  BsatnRowList.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN

/// Represents a list of BSATN-encoded rows
public struct BsatnRowList: Sendable {
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
    
    // Constructor for binary offset-based format used by OneOffQuery responses
    init(reader: BSATNReader) throws {
        debugLog(">>> BsatnRowList: reading binary format with offsets")
        
        // Read size hint
        let sizeHint: UInt8 = try reader.read()
        debugLog(">>>   Size hint: \(sizeHint)")
        
        // Use the existing working parser from CompressibleQueryUpdate
        var rows: [Data] = []
        let rowCount = try Self.readBsatnRowListFormat(reader: reader, into: &rows)
        
        self.rows = rows
        debugLog(">>> BsatnRowList: parsed \(rows.count) rows from binary format")
    }
    
    /// Helper to read BsatnRowList format (same as CompressibleQueryUpdate)
    private static func readBsatnRowListFormat(reader: BSATNReader, into rows: inout [Data]) throws -> Int {
        let offsetCount: UInt32 = try reader.read()

        // Read offset table
        var offsets: [UInt64] = []
        for _ in 0..<offsetCount {
            let offset: UInt64 = try reader.read()
            offsets.append(offset)
        }

        // Read data size
        let dataSize: UInt32 = try reader.read()

        // Read the data blob and split by offsets
        if dataSize > 0 && offsetCount > 0 {
            let dataBlobSlice = try reader.readBytes(Int(dataSize))
            let dataBlob = Data(dataBlobSlice)

            // Offsets indicate the START position of each row in the data blob
            for i in 0..<Int(offsetCount) {
                let startOffset = Int(offsets[i])
                let endOffset = (i + 1 < offsetCount) ? Int(offsets[i + 1]) : dataBlob.count

                // Make sure offsets are valid
                guard startOffset <= dataBlob.count && endOffset <= dataBlob.count && startOffset <= endOffset else {
                    debugLog(">>>   Warning: Invalid offsets for row \(i): start=\(startOffset), end=\(endOffset), dataSize=\(dataBlob.count)")
                    continue
                }

                let rowData = Data(dataBlob[startOffset..<endOffset])
                rows.append(rowData)
            }
        }

        return Int(offsetCount)
    }
}