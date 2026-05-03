//
//  OneOffQueryResponse.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-27.
//

import Foundation
import BSATN

public struct OneOffTable: Sendable {
    public let name: String
    public let rows: [Data]
}

public struct OneOffQueryResponse: Sendable {
    public let messageId: Data
    public let error: String?
    public let tables: [OneOffTable]
    public let totalHostExecutionDuration: UInt64 // microseconds

    init(reader: BSATNReader) throws {
        debugLog(">>> Parsing OneOffQueryResponse at offset \(reader.currentOffset)")
        
        // Read message ID as byte array (Box<[u8]>)
        let messageIdLength: UInt32 = try reader.read()
        debugLog(">>> Message ID length: \(messageIdLength)")
        var messageIdBytes = Data()
        for _ in 0..<messageIdLength {
            let byte: UInt8 = try reader.read()
            messageIdBytes.append(byte)
        }
        self.messageId = messageIdBytes
        debugLog(">>> Message ID: \(messageIdBytes.map { String(format: "%02X", $0) }.joined())")

        // Read error (Option<String>)
        let errorTag: UInt8 = try reader.read()
        debugLog(">>> Error tag: \(errorTag)")
        if errorTag == 0 {
            // Some case - read string
            let errorLength: UInt32 = try reader.read()
            debugLog(">>> Error message length: \(errorLength)")
            var errorBytes = Data()
            for _ in 0..<errorLength {
                let byte: UInt8 = try reader.read()
                errorBytes.append(byte)
            }
            self.error = String(data: errorBytes, encoding: .utf8)
            debugLog(">>> Error message: \(self.error ?? "nil")")
        } else {
            // None case
            self.error = nil
            debugLog(">>> No error message")
        }

        // Read tables array (Box<[OneOffTable]>)
        let tablesCount: UInt32 = try reader.read()
        debugLog(">>> Tables count: \(tablesCount)")
        var tables: [OneOffTable] = []
        
        for tableIndex in 0..<tablesCount {
            debugLog(">>> Reading table \(tableIndex)")
            
            // Read table name
            let nameLength: UInt32 = try reader.read()
            debugLog(">>>   Table name length: \(nameLength)")
            var nameBytes = Data()
            for _ in 0..<nameLength {
                let byte: UInt8 = try reader.read()
                nameBytes.append(byte)
            }
            let tableName = String(data: nameBytes, encoding: .utf8) ?? ""
            debugLog(">>>   Table name: '\(tableName)'")
            
            // Use the existing BsatnRowList parser with new binary format constructor
            debugLog(">>>   Reading BsatnRowList using binary format parser...")
            
            let bsatnRowList = try BsatnRowList(reader: reader)
            
            debugLog(">>>   BsatnRowList parsed successfully with \(bsatnRowList.rows.count) rows")
            
            tables.append(OneOffTable(name: tableName, rows: bsatnRowList.rows))
        }
        
        self.tables = tables

        // Read execution duration
        self.totalHostExecutionDuration = try reader.read()
        debugLog(">>> Execution duration: \(self.totalHostExecutionDuration) microseconds")
        
        debugLog(">>> OneOffQueryResponse parsing complete")
    }
}