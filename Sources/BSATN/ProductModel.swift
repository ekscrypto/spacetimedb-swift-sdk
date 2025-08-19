//
//  ProductModel.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-18.
//

public protocol ProductModel: Sendable {
    var definition: [AlgebraicValueType] { get }
}
