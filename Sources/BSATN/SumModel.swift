//
//  SumModel.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-18.
//

public protocol SumModel: Sendable {
    static var size: UInt32 { get }
}
