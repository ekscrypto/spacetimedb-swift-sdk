//
//  MessageDecompression.swift
//  spacetimedb-swift-sdk
//
//  Brotli + gzip decompression helpers used by the v2 message dispatcher.
//  v2 only compresses entire ServerMessage frames at the WebSocket level;
//  per-table CompressibleQueryUpdate (v1) is gone.
//

import Foundation
import BSATN
import Compression

enum MessageDecompression {
    /// Decompress brotli-encoded bytes via Apple's Compression framework.
    static func brotli(_ data: Data) throws -> Data {
        try decode(data: data, algorithm: COMPRESSION_BROTLI, label: "brotli")
    }

    /// Decompress RFC 1952 gzip bytes by stripping the gzip framing and
    /// running the embedded raw DEFLATE payload through `COMPRESSION_ZLIB`
    /// (Apple's name for raw RFC 1951 deflate, despite the misleading enum).
    static func gzip(_ data: Data) throws -> Data {
        let payload = try stripGzipFraming(data)
        return try decode(data: payload, algorithm: COMPRESSION_ZLIB, label: "gzip(deflate)")
    }

    private static func decode(data: Data, algorithm: compression_algorithm, label: String) throws -> Data {
        let capacity = max(data.count * 50, 1024 * 1024)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }

        let decoded: Data? = data.withUnsafeBytes { src in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let n = compression_decode_buffer(buffer, capacity, base, data.count, nil, algorithm)
            guard n > 0 else { return nil }
            return Data(bytes: buffer, count: n)
        }
        guard let decoded else {
            throw BSATNError.invalidStructure("Failed to decompress \(label) data (\(data.count) bytes)")
        }
        return decoded
    }

    private static func stripGzipFraming(_ data: Data) throws -> Data {
        guard data.count >= 18 else {
            throw BSATNError.invalidStructure("gzip too short (\(data.count) bytes)")
        }
        let base = data.startIndex
        guard data[base] == 0x1f, data[base + 1] == 0x8b else {
            throw BSATNError.invalidStructure("gzip magic mismatch")
        }
        guard data[base + 2] == 8 else {
            throw BSATNError.invalidStructure("gzip method != deflate")
        }
        let flg = data[base + 3]
        var headerLen = 10

        if flg & 0x04 != 0 {
            guard base + headerLen + 2 <= data.endIndex else {
                throw BSATNError.invalidStructure("gzip FEXTRA truncated")
            }
            let xlen = Int(data[base + headerLen]) | (Int(data[base + headerLen + 1]) << 8)
            headerLen += 2 + xlen
        }
        if flg & 0x08 != 0 {
            while base + headerLen < data.endIndex, data[base + headerLen] != 0 {
                headerLen += 1
            }
            headerLen += 1
        }
        if flg & 0x10 != 0 {
            while base + headerLen < data.endIndex, data[base + headerLen] != 0 {
                headerLen += 1
            }
            headerLen += 1
        }
        if flg & 0x02 != 0 { headerLen += 2 }

        let footerLen = 8
        guard headerLen + footerLen <= data.count else {
            throw BSATNError.invalidStructure("gzip header+footer overflow body")
        }
        return data.subdata(in: (base + headerLen)..<(data.endIndex - footerLen))
    }
}
