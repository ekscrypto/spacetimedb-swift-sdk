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

            // Parse the decompressed data as a QueryUpdate. readBsatnRowList
            // now reads the size_hint tag itself — no manual tag pre-read.
            let reader = BSATNReader(data: decompressed, debugEnabled: DebugConfiguration.shared.isEnabled)
            var deleteRows: [Data] = []
            _ = try Self.readBsatnRowList(reader: reader, into: &deleteRows)
            var insertRows: [Data] = []
            _ = try Self.readBsatnRowList(reader: reader, into: &insertRows)
            return QueryUpdate(
                deletes: BsatnRowList(rows: deleteRows),
                inserts: BsatnRowList(rows: insertRows)
            )

        case .gzip(let compressedData):
            debugLog(">>> Decompressing gzip data: \(compressedData.count) bytes")
            let decompressed = try Self.decompressGzip(data: compressedData)
            debugLog(">>> Decompressed to: \(decompressed.count) bytes")
            let reader = BSATNReader(data: decompressed, debugEnabled: DebugConfiguration.shared.isEnabled)
            var deleteRows: [Data] = []
            _ = try Self.readBsatnRowList(reader: reader, into: &deleteRows)
            var insertRows: [Data] = []
            _ = try Self.readBsatnRowList(reader: reader, into: &insertRows)
            return QueryUpdate(
                deletes: BsatnRowList(rows: deleteRows),
                inserts: BsatnRowList(rows: insertRows)
            )
        }
    }

    /// Helper to read BsatnRowList format. Pre-Phase-9-fix this only
    /// handled the `RowOffsets` variant; callers used to read the leading
    /// `tag = 1` byte themselves. The full SpacetimeDB wire format is:
    ///
    ///   BsatnRowList = { size_hint: RowSizeHint, rows_data: [u8] }
    ///   RowSizeHint  = u8 tag
    ///                     0 -> FixedSize(u16)
    ///                     1 -> RowOffsets([u64] = u32 count + count*u64)
    ///   rows_data    = u32 size + size bytes
    ///
    /// This implementation reads the size_hint tag itself and dispatches
    /// to either the fixed-size or offsets-based row split.
    static func readBsatnRowList(reader: BSATNReader, into rows: inout [Data]) throws -> Int {
        let hintTag: UInt8 = try reader.read()
        var fixedSize: UInt16 = 0
        var offsets: [UInt64] = []
        switch hintTag {
        case 0:
            fixedSize = try reader.read()
        case 1:
            let count: UInt32 = try reader.read()
            offsets.reserveCapacity(Int(count))
            for _ in 0..<count {
                let off: UInt64 = try reader.read()
                offsets.append(off)
            }
        default:
            throw BSATNError.unsupportedTag(hintTag)
        }

        let dataSize: UInt32 = try reader.read()
        let dataBlob = dataSize > 0 ? Data(try reader.readBytes(Int(dataSize))) : Data()

        if hintTag == 0 {
            if fixedSize == 0 {
                if !dataBlob.isEmpty { rows.append(dataBlob) }
            } else {
                let stride = Int(fixedSize)
                var i = 0
                while i + stride <= dataBlob.count {
                    rows.append(Data(dataBlob[i..<(i + stride)]))
                    i += stride
                }
            }
        } else {
            for (idx, start) in offsets.enumerated() {
                let s = Int(start)
                let e = (idx + 1 < offsets.count) ? Int(offsets[idx + 1]) : dataBlob.count
                guard s <= e, e <= dataBlob.count else { continue }
                rows.append(Data(dataBlob[s..<e]))
            }
        }
        return rows.count
    }
}