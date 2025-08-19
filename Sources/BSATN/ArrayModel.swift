//
//  ArrayModel.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-18.
//

public protocol ArrayModel: Sendable {
    static var baseType: AlgebraicValueType { get }
}
