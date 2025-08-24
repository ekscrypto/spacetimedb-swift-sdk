//
//  TableRowDecoder.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//


import BSATN

public protocol TableRowDecoder: Sendable {
  var model: ProductModel { get }
  func decode(modelValues: [AlgebraicValue]) throws -> Any
}
