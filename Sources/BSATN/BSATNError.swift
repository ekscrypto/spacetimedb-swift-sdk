//
//  BSATNErrors.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-18.
//

public enum BSATNError: Error {
    case insufficientData
    case notImplemented
    case unsupportedTag(UInt8)
}
