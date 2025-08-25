//
//  CompressibleQueryUpdate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//

import Foundation
import BSATN

/// Represents a query update that can be compressed or uncompressed
public enum CompressibleQueryUpdate {
    case uncompressed(QueryUpdate)
    case brotli(Data)
    case gzip(Data)
    
    /// Get the uncompressed QueryUpdate
    public func getQueryUpdate() throws -> QueryUpdate {
        switch self {
        case .uncompressed(let queryUpdate):
            return queryUpdate
        case .brotli(let compressedData):
            throw BSATNError.invalidStructure("Brotli decompression not implemented (\(compressedData.count) bytes of compressed data). Consider using compression: .none in SpacetimeDBClient")
        case .gzip(let compressedData):
            throw BSATNError.invalidStructure("Gzip decompression not implemented (\(compressedData.count) bytes of compressed data). Consider using compression: .none in SpacetimeDBClient")
        }
    }
}