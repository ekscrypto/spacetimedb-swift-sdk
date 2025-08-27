//
//  TableUpdate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN

public struct TableUpdate {
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
                // Uncompressed: read QueryUpdate with BsatnRowList format
                // Each BsatnRowList starts with a format marker

                // Read deletes BsatnRowList
                let deleteTag: UInt8 = try reader.read()
                debugLog(">>>     Delete tag: \(deleteTag)")

                var deleteRows: [Data] = []
                if deleteTag == 1 {
                    // BsatnRowList format
                    let deleteOffsetCount: UInt32 = try reader.read()
                    debugLog(">>>     Delete offset count: \(deleteOffsetCount)")

                    // Read offset table
                    var deleteOffsets: [UInt64] = []
                    for _ in 0..<deleteOffsetCount {
                        let offset: UInt64 = try reader.read()
                        deleteOffsets.append(offset)
                    }

                    // Read data size
                    let deleteDataSize: UInt32 = try reader.read()
                    debugLog(">>>     Delete data size: \(deleteDataSize)")

                    // Read the data blob and split by offsets
                    if deleteDataSize > 0 && deleteOffsetCount > 0 {
                        let dataBlobSlice = try reader.readBytes(Int(deleteDataSize))
                        let dataBlob = Data(dataBlobSlice)

                        // Offsets indicate the START position of each row in the data blob
                        // Row i starts at deleteOffsets[i] and ends at deleteOffsets[i+1] (or end of blob for last row)
                        for i in 0..<Int(deleteOffsetCount) {
                            let startOffset = Int(deleteOffsets[i])
                            let endOffset = (i + 1 < deleteOffsetCount) ? Int(deleteOffsets[i + 1]) : dataBlob.count

                            // Make sure offsets are valid
                            guard startOffset <= dataBlob.count && endOffset <= dataBlob.count && startOffset <= endOffset else {
                                debugLog(">>>     Warning: Invalid offsets for delete row \(i): start=\(startOffset), end=\(endOffset), dataSize=\(dataBlob.count)")
                                continue
                            }

                            let rowData = Data(dataBlob[startOffset..<endOffset])
                            deleteRows.append(rowData)
                            if rowData.count > 0 {
                                debugLog(">>>     Delete row \(i): \(rowData.count) bytes")
                            }
                        }
                    } else if deleteDataSize > 0 {
                        // Single row with no offset table (entire data is one row)
                        let dataBlobSlice = try reader.readBytes(Int(deleteDataSize))
                        let dataBlob = Data(dataBlobSlice)
                        deleteRows.append(dataBlob)
                        debugLog(">>>     Single delete row: \(dataBlob.count) bytes")
                    }
                } else if deleteTag == 0 {
                    // Empty list
                    debugLog(">>>     Empty delete list")
                } else {
                    debugLog(">>>     Unknown delete format: \(deleteTag)")
                }

                // Read inserts BsatnRowList
                let insertTag: UInt8 = try reader.read()
                debugLog(">>>     Insert tag: \(insertTag)")

                var insertRows: [Data] = []
                if insertTag == 1 {
                    // BsatnRowList format
                    let insertOffsetCount: UInt32 = try reader.read()
                    debugLog(">>>     Insert offset count: \(insertOffsetCount)")

                    // Read offset table
                    var insertOffsets: [UInt64] = []
                    for _ in 0..<insertOffsetCount {
                        let offset: UInt64 = try reader.read()
                        insertOffsets.append(offset)
                        if insertOffsets.count <= 5 {
                            debugLog(">>>       Offset \(insertOffsets.count - 1): \(offset)")
                        }
                    }

                    // Read data size
                    let insertDataSize: UInt32 = try reader.read()
                    debugLog(">>>     Insert data size: \(insertDataSize)")

                    // Read the data blob and split by offsets
                    if insertDataSize > 0 && insertOffsetCount > 0 {
                        let dataBlobSlice = try reader.readBytes(Int(insertDataSize))
                        let dataBlob = Data(dataBlobSlice)

                        // Offsets indicate the START position of each row in the data blob
                        // Row i starts at insertOffsets[i] and ends at insertOffsets[i+1] (or end of blob for last row)
                        for i in 0..<Int(insertOffsetCount) {
                            let startOffset = Int(insertOffsets[i])
                            let endOffset = (i + 1 < insertOffsetCount) ? Int(insertOffsets[i + 1]) : dataBlob.count

                            // Make sure offsets are valid
                            guard startOffset <= dataBlob.count && endOffset <= dataBlob.count && startOffset <= endOffset else {
                                debugLog(">>>     Warning: Invalid offsets for row \(i): start=\(startOffset), end=\(endOffset), dataSize=\(dataBlob.count)")
                                continue
                            }

                            let rowData = Data(dataBlob[startOffset..<endOffset])
                            insertRows.append(rowData)

                            if i < 5 {  // Show first few rows
                                let preview = rowData.prefix(min(50, rowData.count))
                                let hex = preview.map { String(format: "%02X", $0) }.joined(separator: " ")
                                debugLog(">>>     Insert row \(i): \(rowData.count) bytes - \(hex)")
                            }
                        }
                    } else if insertDataSize > 0 {
                        // Single row with no offset table (entire data is one row)
                        let dataBlobSlice = try reader.readBytes(Int(insertDataSize))
                        let dataBlob = Data(dataBlobSlice)
                        insertRows.append(dataBlob)
                        debugLog(">>>     Single insert row: \(dataBlob.count) bytes")
                    }
                } else if insertTag == 0 {
                    // Empty list
                    debugLog(">>>     Empty insert list")
                } else {
                    debugLog(">>>     Unknown insert format: \(insertTag)")
                }


                // Create QueryUpdate directly from the parsed BsatnRowLists
                let queryUpdate = QueryUpdate(
                    deletes: BsatnRowList(rows: deleteRows),
                    inserts: BsatnRowList(rows: insertRows)
                )
                let update = CompressibleQueryUpdate.uncompressed(queryUpdate)
                updates.append(update)

                debugLog(">>>     Parsed uncompressed QueryUpdate: \(deleteRows.count) deletes, \(insertRows.count) inserts")

                // Show first insert if available
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
}
