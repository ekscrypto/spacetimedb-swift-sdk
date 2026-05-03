//
//  BsatnRowList.swift
//  spacetimedb-swift-sdk
//
//  v2 wire format — see crates/client-api-messages/src/websocket/common.rs
//
//  BsatnRowList = { size_hint: RowSizeHint, rows_data: [u8] }
//  RowSizeHint  = u8 tag
//                   0 -> FixedSize(u16)        // every row is N bytes
//                   1 -> RowOffsets([u64])     // u32 count + count*u64
//  rows_data    = u32 size + size bytes
//

import Foundation
import BSATN

public struct BsatnRowList: Sendable {
    public let rows: [Data]

    public init(rows: [Data] = []) {
        self.rows = rows
    }

    init(reader: BSATNReader) throws {
        var collected: [Data] = []
        try Self.read(into: &collected, from: reader)
        self.rows = collected
    }

    /// Parse a `BsatnRowList` from `reader` and append decoded row slices to `rows`.
    static func read(into rows: inout [Data], from reader: BSATNReader) throws {
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

        switch hintTag {
        case 0:
            // FixedSize: split data into stride-sized chunks.
            // fixedSize == 0 with non-empty data is the SpacetimeDB convention
            // for "one row of N bytes" used by zero-field row types.
            if fixedSize == 0 {
                if !dataBlob.isEmpty { rows.append(dataBlob) }
                return
            }
            let stride = Int(fixedSize)
            var i = 0
            while i + stride <= dataBlob.count {
                rows.append(dataBlob.subdata(in: i..<(i + stride)))
                i += stride
            }
        default:
            // RowOffsets: each offset marks the START of a row in dataBlob.
            for (idx, start) in offsets.enumerated() {
                let s = Int(start)
                let e = (idx + 1 < offsets.count) ? Int(offsets[idx + 1]) : dataBlob.count
                guard s <= e, e <= dataBlob.count else { continue }
                rows.append(dataBlob.subdata(in: s..<e))
            }
        }
    }
}
