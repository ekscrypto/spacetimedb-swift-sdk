//
//  IdentityResponse.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation

struct IdentityResponse: Decodable {
    let token: AuthenticationToken
    let identity: Identity
}
