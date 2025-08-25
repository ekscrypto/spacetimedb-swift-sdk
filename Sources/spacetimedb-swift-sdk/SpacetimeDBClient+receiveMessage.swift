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
                
                // Store current identity
                self.currentIdentity = identityToken.identity
                await clientDelegate?.onIdentityReceived(client: self, token: identityToken.token, identity: identityToken.identity)
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
                                // Skip empty row data
                                if row.isEmpty {
                                    continue
                                }
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
                            await clientDelegate?.onTableUpdate(
                                client: self,
                                table: tableUpdate.name,
                                deletes: deletedRows,
                                inserts: insertedRows
                            )
                        } else {
                            print(">>>   No decoder registered for table: \(tableUpdate.name)")
                        }
                    } catch {
                        print(">>>   Error parsing QueryUpdate: \(error)")
                    }
                }
                
                // Notify delegate
                clientDelegate?.onSubscribeMultiApplied(client: self, queryId: subscribeMultiApplied.queryId)
            } else if messageTag == Tags.ServerMessage.transactionUpdate.rawValue {
                // Read TransactionUpdate - pass the reader directly instead of remainingData
                print(">>> Attempting to read TransactionUpdate from offset: \(reader.currentOffset)")
                print(">>> Remaining bytes: \(reader.remainingBytes)")
                
                // Create TransactionUpdate with the reader directly
                let update = try TransactionUpdate(reader: reader)
                
                // Check if this is from another user
                let isOwnUpdate = (update.callerIdentity.description == self.currentIdentity?.description)
                let updateSource = isOwnUpdate ? "OWN" : "OTHER USER"
                
                print(">>> TransactionUpdate from \(updateSource):")
                print(">>>   Reducer: \(update.reducerName)")
                print(">>>   Caller: \(update.callerIdentity.description.prefix(16))...")
                print(">>>   Request ID: \(update.reducerCall.requestId)")
                print(">>>   Status: \(update.eventStatusDescription)")
                
                // Notify delegate about reducer response
                var errorMessage: String? = nil
                if case .failed(let message) = update.status {
                    errorMessage = message
                }
                
                await clientDelegate?.onReducerResponse(
                    client: self,
                    reducer: update.reducerName,
                    requestId: update.reducerCall.requestId,
                    status: update.eventStatusDescription,
                    message: errorMessage,
                    energyUsed: update.energyQuantaUsed.used
                )
                
                // Name changes will be detected and displayed by the delegate
                // when it compares the cached names with the new data
                
                // Process database updates
                for tableUpdate in update.databaseUpdate.tableUpdates {
                    print(">>>   Table: \(tableUpdate.name) with \(tableUpdate.queryUpdates.count) query updates")
                    
                    // Get the decoder for this table
                    let decoder = decoder(forTable: tableUpdate.name)
                    
                    // Collect ALL deletes and inserts for this table across all QueryUpdates
                    var allDeletedRows: [Any] = []
                    var allInsertedRows: [Any] = []
                    
                    // Process each CompressibleQueryUpdate in the table
                    for compUpdate in tableUpdate.queryUpdates {
                        guard case .uncompressed(let queryUpdate) = compUpdate else {
                            print(">>>     Warning: Compressed updates not yet supported")
                            continue
                        }
                        
                        print(">>>     QueryUpdate: \(queryUpdate.deletes.rows.count) deletes, \(queryUpdate.inserts.rows.count) inserts")
                        
                        // Debug: Check row data sizes
                        for (idx, row) in queryUpdate.deletes.rows.enumerated() {
                            print(">>>       Delete row \(idx): \(row.count) bytes")
                        }
                        for (idx, row) in queryUpdate.inserts.rows.enumerated() {
                            print(">>>       Insert row \(idx): \(row.count) bytes")
                        }
                        
                        // Process deletes
                        if !queryUpdate.deletes.rows.isEmpty {
                            if let decoder {
                                for row in queryUpdate.deletes.rows {
                                    // Skip empty row data (common in TransactionUpdate)
                                    if row.isEmpty {
                                        continue
                                    }
                                    do {
                                        let reader = BSATNReader(data: row)
                                        let modelValue = try reader.readAlgebraicValue(as: .product(decoder.model))
                                        guard case .product(let values) = modelValue else { continue }
                                        let typedRow = try decoder.decode(modelValues: values)
                                        allDeletedRows.append(typedRow)
                                    } catch {
                                        print(">>>     Error decoding deleted row: \(error)")
                                    }
                                }
                            } else {
                                // No decoder, pass raw data
                                for row in queryUpdate.deletes.rows where !row.isEmpty {
                                    allDeletedRows.append(row)
                                }
                            }
                        }
                        
                        // Process inserts
                        if !queryUpdate.inserts.rows.isEmpty {
                            if let decoder {
                                for row in queryUpdate.inserts.rows {
                                    // Skip empty row data (common in TransactionUpdate)
                                    if row.isEmpty {
                                        continue
                                    }
                                    do {
                                        let reader = BSATNReader(data: row)
                                        let modelValue = try reader.readAlgebraicValue(as: .product(decoder.model))
                                        guard case .product(let values) = modelValue else { continue }
                                        let typedRow = try decoder.decode(modelValues: values)
                                        allInsertedRows.append(typedRow)
                                        if !isOwnUpdate {
                                            print(">>>     📢 New row from OTHER USER: \(typedRow)")
                                        } else {
                                            print(">>>     New row (own update): \(typedRow)")
                                        }
                                    } catch {
                                        print(">>>     Error decoding inserted row: \(error)")
                                    }
                                }
                            } else {
                                // No decoder, pass raw data
                                for row in queryUpdate.inserts.rows where !row.isEmpty {
                                    allInsertedRows.append(row)
                                }
                            }
                        }
                    }
                    
                    // Always call the delegate if we have any rows (even if just raw data)
                    if !allDeletedRows.isEmpty || !allInsertedRows.isEmpty {
                        print(">>>   Calling onTableUpdate for '\(tableUpdate.name)': \(allDeletedRows.count) deletes, \(allInsertedRows.count) inserts")
                        await clientDelegate?.onTableUpdate(
                            client: self,
                            table: tableUpdate.name,
                            deletes: allDeletedRows,
                            inserts: allInsertedRows
                        )
                    } else {
                        print(">>>   No rows to report for table '\(tableUpdate.name)'")
                    }
                }
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
