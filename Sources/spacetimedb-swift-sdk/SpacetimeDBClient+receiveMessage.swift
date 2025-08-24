//
//  SpacetimeDBClient+receiveMessage.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-10.
//

import Foundation
import BSATN

extension SpacetimeDBClient {
    internal func receiveMessage() async throws {
        guard let webSocketTask else {
            return
        }

    receiveNextMessage:
        while !Task.isCancelled {
            let message = try await webSocketTask.receive()
            switch message {
            case .data(let data):
                await processOrForwardMessage(data)
            case .string(let string):
                guard let data = string.data(using: .utf8) else {
                    continue receiveNextMessage
                }
                await processOrForwardMessage(data)
            @unknown default:
                break
            }
        }
    }

    private func processOrForwardMessage(_ data: Data) async {
        // Display hex representation of the data before processing
        if DEBUG_HEX_VIEW {
            print("=== Received BSATN Message ===")
            printHexData(data)
            print("==============================")
        }
        
        // Process the BSATN message
        let reader = BSATNReader(data: data)
        
        // Read compression tag (should be 0 for none)
        let compressionTag: UInt8 = (try? reader.read()) ?? 0
        if compressionTag != Tags.Compression.none.rawValue {
            print(">>> Warning: Compressed messages not yet supported (compression: \(compressionTag))")
            return
        }
        
        // Read message type tag
        let messageTag: UInt8 = (try? reader.read()) ?? 0
        print(">>> Message type: \(messageTag)")
        
        do {
            if messageTag == Tags.ServerMessage.identityToken.rawValue {
                // Read IdentityTokenMessage
                let identityToken = try IdentityTokenMessage(modelValues: [
                    try reader.readAlgebraicValue(as: .uint256),
                    try reader.readAlgebraicValue(as: .string),
                    try reader.readAlgebraicValue(as: .uint128)
                ])
                print(">>> Identity: \(identityToken)")
                
                // Notify delegate about the identity token
                let identityHex = identityToken.identity.description
                await clientDelegate?.onIdentityReceived(client: self, token: identityToken.token, identity: identityHex)
            } else if messageTag == Tags.ServerMessage.subscribeMultiApplied.rawValue {
                // Read SubscribeMultiApplied directly from reader
                let subscribeMultiApplied = try SubscribeMultiApplied(reader: reader)
                print(">>> SubscribeMultiApplied: requestId=\(subscribeMultiApplied.requestId), tables=\(subscribeMultiApplied.update.tableUpdates.count)")
                
                for tableUpdate in subscribeMultiApplied.update.tableUpdates {
                    print(">>> Table: \(tableUpdate.name) (id: \(tableUpdate.id), rows: \(tableUpdate.numRows))")
                    
                    do {
                        let queryUpdate = try tableUpdate.getQueryUpdate()
                        print(">>>   Deletes: \(queryUpdate.deletes.rows.count) rows")
                        print(">>>   Inserts: \(queryUpdate.inserts.rows.count) rows")
                        
                        let decoder = decoder(forTable: tableUpdate.name)
                        if let decoder {
                            // Process inserts
                            var insertedRows: [Any] = []
                            for (index, row) in queryUpdate.inserts.rows.enumerated() {
                                do {
                                    let reader = BSATNReader(data: row)
                                    let modelValue = try reader.readAlgebraicValue(as: .product(decoder.model))
                                    guard case .product(let values) = modelValue else { continue }
                                    let typedRow = try decoder.decode(modelValues: values)
                                    insertedRows.append(typedRow)
                                    print(">>>     Row \(index) for \(tableUpdate.name): \(typedRow)")
                                } catch {
                                    print(">>>     Error decoding row \(index): \(error)")
                                }
                            }
                            
                            // Process deletes
                            var deletedRows: [Any] = []
                            for (index, row) in queryUpdate.deletes.rows.enumerated() {
                                do {
                                    let reader = BSATNReader(data: row)
                                    let modelValue = try reader.readAlgebraicValue(as: .product(decoder.model))
                                    guard case .product(let values) = modelValue else { continue }
                                    let typedRow = try decoder.decode(modelValues: values)
                                    deletedRows.append(typedRow)
                                } catch {
                                    print(">>>     Error decoding deleted row \(index): \(error)")
                                }
                            }
                            
                            // Notify delegate
                            if !insertedRows.isEmpty {
                                await clientDelegate?.onRowsInserted(client: self, table: tableUpdate.name, rows: insertedRows)
                            }
                            if !deletedRows.isEmpty {
                                await clientDelegate?.onRowsDeleted(client: self, table: tableUpdate.name, rows: deletedRows)
                            }
                        } else {
                            print(">>>   No decoder registered for table: \(tableUpdate.name)")
                        }
                    } catch {
                        print(">>>   Error parsing QueryUpdate: \(error)")
                    }
                }
                
                // Notify delegate
                clientDelegate?.onSubscribeMultiApplied(client: self, queryId: subscribeMultiApplied.queryId)
            }
        } catch {
            print(">>> Failed to decode: \(error)")
        }

        let onIncomingMessage = clientDelegate?.onIncomingMessage
        await onIncomingMessage?(self, data)
    }
    
    // MARK: - Hexadecimal Data Viewer
    
    /// Set to true to enable hex viewing of incoming messages
    private var DEBUG_HEX_VIEW: Bool { true }
    
    /// Display data in hexadecimal format (16 bytes per line with offsets)
    private func printHexData(_ data: Data) {
        let bytes = Array(data)
        let bytesPerLine = 16
        
        for i in stride(from: 0, to: bytes.count, by: bytesPerLine) {
            // Print offset in hex
            print(String(format: "0x%08X: ", i), terminator: "")
            
            // Print hex bytes
            for j in 0..<bytesPerLine {
                if i + j < bytes.count {
                    print(String(format: "%02X ", bytes[i + j]), terminator: "")
                } else {
                    print("   ", terminator: "") // Padding for missing bytes
                }
                
                // Add extra space between groups of 8 bytes for readability
                if j == 7 && i + j < bytes.count {
                    print(" ", terminator: "")
                }
            }
            
            // Print ASCII representation
            print(" |", terminator: "")
            for j in 0..<bytesPerLine {
                if i + j < bytes.count {
                    let byte = bytes[i + j]
                    if byte >= 32 && byte <= 126 { // Printable ASCII range
                        print(String(format: "%c", byte), terminator: "")
                    } else {
                        print(".", terminator: "")
                    }
                } else {
                    print(" ", terminator: "")
                }
            }
            print("|")
        }
        
        print(String(format: "Total bytes: %d (0x%X)", data.count, data.count))
    }
}