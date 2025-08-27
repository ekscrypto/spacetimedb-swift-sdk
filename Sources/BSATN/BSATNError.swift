//
//  BSATNErrors.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-18.
//

public enum BSATNError: Error, Equatable {
    case insufficientData
    case notImplemented
    case unsupportedTag(UInt8)
    case invalidStructure(String)
    case invalidSumTag(UInt8)
}