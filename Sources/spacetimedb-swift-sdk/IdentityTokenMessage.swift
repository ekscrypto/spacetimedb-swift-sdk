//
//  IdentityTokenMessage.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation
import BSATN

struct IdentityTokenMessage: Codable {
    let identityToken: IdentityTokenPayload

    enum CodingKeys: String, CodingKey {
        case identityToken = "IdentityToken"
    }

    struct IdentityTokenPayload: Codable {
        let identity: EmbeddedIdentity
        let token: String
        // Re-enabling connectionId now that we have proper BSATN support
        let connectionId: EmbeddedConnectionId

        enum CodingKeys: String, CodingKey {
            case identity
            case token
            case connectionId = "connection_id"
        }

        struct EmbeddedIdentity: Codable {
            enum CodingKeys: String, CodingKey {
                case identity = "__identity__"
            }

            let identity: String
        }

        struct EmbeddedConnectionId: Codable {
            enum CodingKeys: String, CodingKey {
                case connectionId = "__connection_id__"
            }

            let connectionId: UInt128
        }
    }
}