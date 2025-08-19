//
//  Compression.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-18.
//

enum Compression: UInt8 {
    case uncompressed
    case brotli
    case gzip
}
