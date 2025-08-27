//
//  UpdateStatus.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-24.
//

import Foundation
import BSATN

/// The status of an update - contains DatabaseUpdate if committed
public enum UpdateStatus {
    case committed(DatabaseUpdate)
    case failed(String)
    case outOfEnergy

    public var description: String {
        switch self {
        case .committed:
            return "committed"
        case .failed(let error):
            return "failed: \(error)"
        case .outOfEnergy:
            return "out of energy"
        }
    }

    init(reader: BSATNReader) throws {
        let tag: UInt8 = try reader.read()
        debugLog(">>>   UpdateStatus tag: \(tag)")
        switch tag {
        case 0:
            // Committed includes a DatabaseUpdate
            debugLog(">>>   Status is committed, reading DatabaseUpdate...")
            let dbUpdate = try DatabaseUpdate(reader: reader)
            self = .committed(dbUpdate)
        case 1:
            // Failed includes an error message
            let message = try reader.readString()
            self = .failed(message)
        case 2:
            // OutOfEnergy has no additional data
            self = .outOfEnergy
        default:
            throw BSATNError.unsupportedTag(tag)
        }
    }
}