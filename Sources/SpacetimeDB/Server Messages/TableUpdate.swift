//
//  TableUpdate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN

public struct TableUpdate: Sendable {
    public let id: UInt32
    public let name: String
    public let numRows: UInt64
    public let queryUpdates: [CompressibleQueryUpdate]  // Array of updates

    struct Model: ProductModel {
        var definition: [AlgebraicValueType] { [
            .uint32,
            .string,
            .uint64,
            .array(ArrayModel { .sum(DummySumModel()) })  // Array of CompressibleQueryUpdate sum types
        ]}
    }

    // Dummy sum model for CompressibleQueryUpdate
    struct DummySumModel: SumModel {
        static var size: UInt32 { 0 }
    }

    // Custom array model wrapper
    struct ArrayModel: BSATN.ArrayModel {
        let elementDef: @Sendable () -> AlgebraicValueType
        var definition: AlgebraicValueType {
            elementDef()
        }
        init(_ def: @escaping @Sendable () -> AlgebraicValueType) {
            self.elementDef = def
        }
    }

    init(modelValues: [AlgebraicValue]) throws {
        let model = Model()
        debugLog("Will be decoding TableUpdate from values: \(modelValues)")
        guard modelValues.count == model.definition.count,
              case .uint32(let tableId) = modelValues[0],
              case .string(let tableName) = modelValues[1],
              case .uint64(let numRows) = modelValues[2]
        else {
            throw SpacetimeDBErrors.invalidDefinition(model)
        }

        self.id = tableId
        self.name = tableName
        self.numRows = numRows

        // For the array of CompressibleQueryUpdate, we need custom parsing
        // because each element is a sum type with different variant structures
        guard case .array(let updateArray) = modelValues[3] else {
            throw SpacetimeDBErrors.invalidDefinition(model)
        }

        debugLog(">>> TableUpdate: id=\(tableId), name='\(tableName)', numRows=\(numRows), updates=\(updateArray.count)")

        // Parse each CompressibleQueryUpdate from the array
        let updates: [CompressibleQueryUpdate] = []
        for (index, updateValue) in updateArray.enumerated() {
            guard case .sum(let tag, _) = updateValue else {
                debugLog(">>>   Update \(index): Expected sum type, got \(updateValue)")
                continue
            }

            debugLog(">>>   Update \(index): tag=\(tag)")

            // For tag 0 (uncompressed), we need to read the QueryUpdate data
            // The sum value has empty data because BSATNReader doesn't know the context
            // We need to provide a way to read the variant data based on the tag

            // Since we can't read the data properly yet, skip for now
            debugLog(">>>   Warning: Cannot parse CompressibleQueryUpdate variant data yet")
        }

        self.queryUpdates = updates
    }

    // Alternative init that reads directly from BSATNReader
    init(reader: BSATNReader) throws {
        self.id = try reader.read()
        self.name = try reader.readString()
        self.numRows = try reader.read()

        // Read array of CompressibleQueryUpdate
        let updateCount: UInt32 = try reader.read()
        debugLog(">>> TableUpdate: id=\(id), name='\(name)', numRows=\(numRows), updates=\(updateCount)")

        var updates: [CompressibleQueryUpdate] = []
        for i in 0..<updateCount {
            // Read tag for sum type
            let tag: UInt8 = try reader.read()
            debugLog(">>>   Update \(i): tag=\(tag)")

            if tag == 0 {
                // Uncompressed: read QueryUpdate consisting of two BsatnRowLists
                // (deletes, inserts). Wire format per the SpacetimeDB
                // client-api spec (see crates/client-api-messages):
                //
                //   BsatnRowList = { size_hint: RowSizeHint, rows_data: [u8] }
                //   RowSizeHint  = u8 tag
                //                     0 -> FixedSize(u16)        // every row is N bytes
                //                     1 -> RowOffsets([u64])     // u32 count + count * u64
                //   rows_data    = u32 size + size bytes
                let deleteRows = try Self.readBsatnRowList(label: "delete", reader: reader)
                let insertRows = try Self.readBsatnRowList(label: "insert", reader: reader)

                let queryUpdate = QueryUpdate(
                    deletes: BsatnRowList(rows: deleteRows),
                    inserts: BsatnRowList(rows: insertRows)
                )
                let update = CompressibleQueryUpdate.uncompressed(queryUpdate)
                updates.append(update)

                debugLog(">>>     Parsed uncompressed QueryUpdate: \(deleteRows.count) deletes, \(insertRows.count) inserts")
                if let firstInsert = insertRows.first, firstInsert.count > 0 {
                    let preview = firstInsert.prefix(min(100, firstInsert.count))
                    let hex = preview.map { String(format: "%02X", $0) }.joined(separator: " ")
                    debugLog(">>>     First insert preview: \(hex)")
                }
            } else if tag == 1 {
                // Brotli compressed
                let compressedSize: UInt32 = try reader.read()
                let compressedData = try reader.readBytes(Int(compressedSize))
                let update = CompressibleQueryUpdate.brotli(Data(compressedData))
                updates.append(update)
                debugLog(">>>     Brotli compressed QueryUpdate: \(compressedSize) bytes")
            } else if tag == 2 {
                // Gzip compressed
                let compressedSize: UInt32 = try reader.read()
                let compressedData = try reader.readBytes(Int(compressedSize))
                let update = CompressibleQueryUpdate.gzip(Data(compressedData))
                updates.append(update)
                debugLog(">>>     Gzip compressed QueryUpdate: \(compressedSize) bytes")
            } else {
                // Unknown compression tag
                throw BSATNError.unsupportedTag(tag)
            }
        }

        self.queryUpdates = updates
    }

    /// Get the first uncompressed QueryUpdate, throwing an error if compressed or empty
    func getQueryUpdate() throws -> QueryUpdate {
        guard let firstUpdate = queryUpdates.first else {
            throw BSATNError.invalidStructure("No query updates in TableUpdate")
        }
        return try firstUpdate.getQueryUpdate()
    }

    /// Read a `BsatnRowList` per the official wire format:
    ///
    ///   size_hint: RowSizeHint = u8 tag + variant payload
    ///                              0 -> FixedSize(u16)
    ///                              1 -> RowOffsets(u32 count + [u64; count])
    ///   rows_data: u32 length + [u8; length]
    ///
    /// Splits `rows_data` into per-row Data slices using the size hint.
    internal static func readBsatnRowList(label: String, reader: BSATNReader) throws -> [Data] {
        let hintTag: UInt8 = try reader.read()
        debugLog(">>>     \(label) hint tag: \(hintTag)")

        var fixedSize: UInt16 = 0
        var offsets: [UInt64] = []
        switch hintTag {
        case 0:
            // FixedSize(u16): every row in rows_data is this many bytes.
            fixedSize = try reader.read()
            debugLog(">>>     \(label) fixed row size: \(fixedSize)")
        case 1:
            // RowOffsets([u64]): explicit start offset of each row in rows_data.
            let count: UInt32 = try reader.read()
            debugLog(">>>     \(label) offset count: \(count)")
            offsets.reserveCapacity(Int(count))
            for _ in 0..<count {
                let off: UInt64 = try reader.read()
                offsets.append(off)
            }
        default:
            throw BSATNError.unsupportedTag(hintTag)
        }

        let dataSize: UInt32 = try reader.read()
        debugLog(">>>     \(label) data size: \(dataSize)")
        let dataBlob = dataSize > 0 ? Data(try reader.readBytes(Int(dataSize))) : Data()

        var rows: [Data] = []
        if hintTag == 0 {
            // FixedSize: split into chunks of `fixedSize` bytes.
            // fixedSize == 0 with non-zero data means "1 row of N bytes" per
            // SpacetimeDB convention; with zero data it means "no rows."
            if fixedSize == 0 {
                if dataBlob.isEmpty {
                    return rows
                }
                rows.append(dataBlob)
                return rows
            }
            let stride = Int(fixedSize)
            var i = 0
            while i + stride <= dataBlob.count {
                rows.append(Data(dataBlob[i..<(i + stride)]))
                i += stride
            }
            if i != dataBlob.count {
                debugLog(">>>     warning: \(label) fixed-size leftover \(dataBlob.count - i) bytes")
            }
        } else {
            // RowOffsets: each offset is the START of a row in dataBlob.
            for (idx, start) in offsets.enumerated() {
                let s = Int(start)
                let e = (idx + 1 < offsets.count) ? Int(offsets[idx + 1]) : dataBlob.count
                guard s <= e, e <= dataBlob.count else {
                    debugLog(">>>     warning: invalid \(label) offsets [\(s)..\(e)] for size \(dataBlob.count)")
                    continue
                }
                rows.append(Data(dataBlob[s..<e]))
            }
        }
        return rows
    }
}
