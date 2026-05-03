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
public enum CompressibleQueryUpdate: Sendable {
    case uncompressed(QueryUpdate)
    case brotli(Data)
    case gzip(Data)

    /// Decompress Brotli data using native Compression framework (iOS 15+/macOS 12+)
    private static func decompressBrotli(data: Data) throws -> Data {
        try decompress(data: data, algorithm: COMPRESSION_BROTLI, label: "Brotli")
    }

    /// Decompress gzip-formatted (RFC 1952) data: parse the gzip header,
    /// feed the embedded raw DEFLATE payload through Apple's
    /// `COMPRESSION_ZLIB` (which despite the name decodes RFC 1951 raw
    /// DEFLATE — see Apple's compression_algorithm docs), and discard
    /// the 8-byte CRC32+ISIZE footer.
    internal static func decompressGzip(data: Data) throws -> Data {
        let payload = try stripGzipFraming(data)
        return try decompress(data: payload, algorithm: COMPRESSION_ZLIB, label: "gzip(deflate)")
    }

    /// Strip the gzip header (variable length) and the 8-byte trailer.
    /// Returns the embedded raw DEFLATE payload bytes.
    internal static func stripGzipFraming(_ data: Data) throws -> Data {
        guard data.count >= 18 else {
            throw BSATNError.invalidStructure("gzip too short (\(data.count) bytes)")
        }
        guard data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else {
            throw BSATNError.invalidStructure("gzip magic mismatch")
        }
        guard data[data.startIndex + 2] == 8 else {
            throw BSATNError.invalidStructure("gzip method != deflate")
        }
        let flg = data[data.startIndex + 3]
        var headerLen = 10
        let bytes = data
        let base = data.startIndex
        if flg & 0x04 != 0 {                             // FEXTRA
            guard base + headerLen + 2 <= bytes.endIndex else {
                throw BSATNError.invalidStructure("gzip FEXTRA truncated")
            }
            let xlen = Int(bytes[base + headerLen]) | (Int(bytes[base + headerLen + 1]) << 8)
            headerLen += 2 + xlen
        }
        if flg & 0x08 != 0 {                             // FNAME (zero-terminated)
            while base + headerLen < bytes.endIndex, bytes[base + headerLen] != 0 {
                headerLen += 1
            }
            headerLen += 1
        }
        if flg & 0x10 != 0 {                             // FCOMMENT (zero-terminated)
            while base + headerLen < bytes.endIndex, bytes[base + headerLen] != 0 {
                headerLen += 1
            }
            headerLen += 1
        }
        if flg & 0x02 != 0 { headerLen += 2 }            // FHCRC

        let footerLen = 8                                // CRC32 + ISIZE
        guard headerLen + footerLen <= bytes.count else {
            throw BSATNError.invalidStructure("gzip header+footer overflow body")
        }
        let payloadStart = base + headerLen
        let payloadEnd = bytes.endIndex - footerLen
        return Data(bytes[payloadStart..<payloadEnd])
    }

    /// Generic compression_decode_buffer wrapper; used by Brotli + gzip paths.
    private static func decompress(data: Data, algorithm: compression_algorithm, label: String) throws -> Data {
        let decodedCapacity = max(data.count * 50, 1024 * 1024)
        let decodedBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: decodedCapacity)
        defer { decodedBuffer.deallocate() }

        let decodedData: Data? = data.withUnsafeBytes { sourceBuffer in
            guard let sourcePtr = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }
            let decompressedSize = compression_decode_buffer(
                decodedBuffer, decodedCapacity,
                sourcePtr, data.count,
                nil, algorithm
            )
            guard decompressedSize > 0 else { return nil }
            return Data(bytes: decodedBuffer, count: decompressedSize)
        }

        guard let decompressed = decodedData else {
            throw BSATNError.invalidStructure("Failed to decompress \(label) data (\(data.count) bytes)")
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

        case .gzip(let compressedData):
            debugLog(">>> Decompressing gzip data: \(compressedData.count) bytes")
            let decompressed = try Self.decompressGzip(data: compressedData)
            debugLog(">>> Decompressed to: \(decompressed.count) bytes")

            let reader = BSATNReader(data: decompressed, debugEnabled: DebugConfiguration.shared.isEnabled)

            let deleteTag: UInt8 = try reader.read()
            var deleteRows: [Data] = []
            if deleteTag == 1 {
                _ = try Self.readBsatnRowList(reader: reader, into: &deleteRows)
            }
            let insertTag: UInt8 = try reader.read()
            var insertRows: [Data] = []
            if insertTag == 1 {
                _ = try Self.readBsatnRowList(reader: reader, into: &insertRows)
            }
            return QueryUpdate(
                deletes: BsatnRowList(rows: deleteRows),
                inserts: BsatnRowList(rows: insertRows)
            )
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