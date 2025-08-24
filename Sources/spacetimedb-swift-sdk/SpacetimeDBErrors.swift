//
//  SpacetimeDBErrors.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-18.
//

import BSATN

public enum SpacetimeDBErrors: Error {
    case invalidDefinition(ProductModel)
    case notConnected
}