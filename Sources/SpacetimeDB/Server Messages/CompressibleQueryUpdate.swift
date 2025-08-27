//
//  CompressibleQueryUpdate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN
import Compression

/// Represents a query update that can be compressed or uncompressed
public enum CompressibleQueryUpdate {
    case uncompressed(QueryUpdate)
    case brotli(Data)
    case gzip(Data)

    /// Decompress Brotli data using native Compression framework (iOS 15+/macOS 12+)
    private static func decompressBrotli(data: Data) throws -> Data {
        // Estimate decompressed size - use a much larger buffer for safety
        let decodedCapacity = max(data.count * 50, 1024 * 1024) // At least 1MB buffer
        let decodedBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: decodedCapacity)
        defer { decodedBuffer.deallocate() }

        let decodedData: Data? = data.withUnsafeBytes { sourceBuffer in
            guard let sourcePtr = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }

            let decompressedSize = compression_decode_buffer(
                decodedBuffer, decodedCapacity,
                sourcePtr, data.count,
                nil, COMPRESSION_BROTLI
            )

            guard decompressedSize > 0 else { return nil }
            return Data(bytes: decodedBuffer, count: decompressedSize)
        }

        guard let decompressed = decodedData else {
            throw BSATNError.invalidStructure("Failed to decompress Brotli data (\(data.count) bytes)")
        }

        return decompressed
    }

    /// Get the uncompressed QueryUpdate
    public func getQueryUpdate() throws -> QueryUpdate {
        switch self {
        case .uncompressed(let queryUpdate):
            return queryUpdate

        case .brotli(let compressedData):
            debugLog(">>> Decompressing Brotli data: \(compressedData.count) bytes")
            let decompressed = try Self.decompressBrotli(data: compressedData)
            debugLog(">>> Decompressed to: \(decompressed.count) bytes")

            // Parse the decompressed data as a QueryUpdate
            let reader = BSATNReader(data: decompressed, debugEnabled: DebugConfiguration.shared.isEnabled)

            // Read deletes BsatnRowList
            let deleteTag: UInt8 = try reader.read()
            var deleteRows: [Data] = []
            if deleteTag == 1 {
                // BsatnRowList format - read offsets and data
                let deleteCount = try Self.readBsatnRowList(reader: reader, into: &deleteRows)
                debugLog(">>>   Read \(deleteCount) delete rows")
            }

            // Read inserts BsatnRowList
            let insertTag: UInt8 = try reader.read()
            var insertRows: [Data] = []
            if insertTag == 1 {
                // BsatnRowList format - read offsets and data
                let insertCount = try Self.readBsatnRowList(reader: reader, into: &insertRows)
                debugLog(">>>   Read \(insertCount) insert rows")
            }

            return QueryUpdate(
                deletes: BsatnRowList(rows: deleteRows),
                inserts: BsatnRowList(rows: insertRows)
            )

        case .gzip(_):
            throw BSATNError.invalidStructure("Gzip compression is not currently supported")
        }
    }

    /// Helper to read BsatnRowList format
    private static func readBsatnRowList(reader: BSATNReader, into rows: inout [Data]) throws -> Int {
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