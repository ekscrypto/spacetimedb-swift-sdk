//
//  TransactionUpdate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-24.
//

import Foundation
import BSATN

/// Represents a transaction update from the server after a reducer execution
public struct TransactionUpdate {
    public let status: UpdateStatus
    public let timestamp: UInt64
    public let callerIdentity: UInt256
    public let callerConnectionId: UInt128  // Note: This is connection ID, not address
    public let reducerCall: ReducerCallInfo
    public let energyQuantaUsed: EnergyQuanta
    public let totalHostExecutionDuration: UInt64  // Duration in microseconds
    
    // Computed properties for compatibility
    public var eventStatusDescription: String {
        return status.description
    }
    
    public var reducerName: String {
        return reducerCall.reducerName
    }
    
    public var reducerArgs: Data {
        return reducerCall.args
    }
    
    public var energyUsed: EnergyQuanta {
        return energyQuantaUsed
    }
    
    public var databaseUpdate: DatabaseUpdate {
        // Extract from status if committed
        if case .committed(let update) = status {
            return update
        }
        // Return empty update if not committed
        return DatabaseUpdate(tableUpdates: [])
    }
    
    
    public struct EnergyQuanta {
        public let budget: UInt128
        public let used: UInt128
        
        init(reader: BSATNReader) throws {
            // Based on actual server bytes, energy might be encoded differently
            // Let's try reading as a single UInt128 that represents used energy
            // with budget being implicit or zero
            let energyValue: UInt128 = try reader.read()
            self.used = energyValue
            self.budget = UInt128() // Budget might not be sent
            print(">>> Energy quanta: used=\(self.used)")
        }
    }
    
    public init(data: Data) throws {
        let reader = BSATNReader(data: data)
        try self.init(reader: reader)
    }
    
    public init(reader: BSATNReader) throws {
        // Based on TypeScript SDK, the field order is:
        // 1. status (UpdateStatus - sum type that contains DatabaseUpdate if committed)
        // 2. timestamp
        // 3. callerIdentity
        // 4. callerConnectionId
        // 5. reducerCall (ReducerCallInfo)
        // 6. energyQuantaUsed
        // 7. totalHostExecutionDuration
        
        print(">>> Parsing TransactionUpdate at offset: \(reader.currentOffset), remaining: \(reader.remainingBytes) bytes")
        
        // Read status (which includes DatabaseUpdate if committed)
        print(">>>   Reading status...")
        self.status = try UpdateStatus(reader: reader)
        print(">>>   Status: \(status.description)")
        
        // Read timestamp
        print(">>>   Reading timestamp...")
        self.timestamp = try reader.read()
        print(">>>   Timestamp: \(timestamp)")
        
        // Read caller identity
        print(">>>   Reading caller identity...")
        self.callerIdentity = try reader.read()
        print(">>>   Caller: \(callerIdentity.description.prefix(16))...")
        
        // Read caller connection ID  
        print(">>>   Reading connection ID...")
        self.callerConnectionId = try reader.read()
        
        // Read reducer call info
        print(">>>   Reading reducer call info...")
        self.reducerCall = try ReducerCallInfo(reader: reader)
        print(">>>   Reducer: \(reducerCall.reducerName)")
        
        // Read energy quanta used
        print(">>>   Reading energy quanta...")
        self.energyQuantaUsed = try EnergyQuanta(reader: reader)
        
        // Read total host execution duration
        print(">>>   Reading execution duration...")
        self.totalHostExecutionDuration = try reader.read()
        print(">>>   Duration: \(totalHostExecutionDuration) microseconds")
        
        print(">>> TransactionUpdate parsed successfully!")
    }
}