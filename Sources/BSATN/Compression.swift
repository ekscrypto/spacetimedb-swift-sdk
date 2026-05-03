//
//  Compression.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-18.
//

public enum Compression: UInt8, CaseIterable, Sendable {
    case none = 0
    case brotli = 1
    case gzip = 2

    // String representation for server communication
    public var serverString: String {
        switch self {
        case .none: return "None"
        case .gzip: return "Gzip"
        case .brotli: return "Brotli"
        }
    }
}
