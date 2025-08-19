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
        let messageHandler = BSATNMessageHandler(supportedTags: [
            Tags.identityToken.rawValue: IdentityTokenMessage.Model()
        ])
        do {
            let message = try messageHandler.processMessage(data)
            if message.tag == Tags.identityToken.rawValue {
                let identityToken = try IdentityTokenMessage(modelValues: message.values)
                print(">>> Identity: \(identityToken)")
            }
        } catch {
            print(">>> Failed to decode: \(error)")
        }

        let onIncomingMessage = clientDelegate?.onIncomingMessage
        await onIncomingMessage?(data)
    }
    
    // MARK: - Hexadecimal Data Viewer
    
    /// Set to true to enable hex viewing of incoming messages
    private var DEBUG_HEX_VIEW: Bool { true }
    
    /// Display data in hexadecimal format (16 bytes per line with offsets)
    private func printHexData(_ data: Data) {
        let bytes = Array(data)
        let bytesPerLine = 16
        
        for i in stride(from: 0, to: bytes.count, by: bytesPerLine) {
            // Print offset
            print(String(format: "%08X: ", i), terminator: "")
            
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
        
        print("Total bytes: \(data.count)")
    }
}
