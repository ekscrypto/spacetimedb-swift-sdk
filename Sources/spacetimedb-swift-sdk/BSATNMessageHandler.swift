import Foundation
import BSATN

/// Handler for processing BSATN-encoded messages from SpacetimeDB
class BSATNMessageHandler {
    /// Process a BSATN message and attempt to decode it
    static func processMessage(_ data: Data) -> BSATNMessageResult {
        // Display hex representation for debugging
        if DEBUG_HEX_VIEW {
            print("=== BSATN Message Processing ===")
            printHexData(data)
            print("===============================")
        }
        
        // Try to decode as a BSATN message
        do {
            let reader = BSATNReader(data: data)
            
            // For now, just demonstrate reading basic types
            // In a real implementation, you'd need to know the message format
            var decodedValues: [String] = []
            
            while reader.hasMoreData {
                // Try to read different types based on what's expected
                // This is a simplified example - real implementation would depend on message format
                if reader.remainingBytes >= 16 {
                    // Try to read as UInt128
                    let uint128 = try reader.readUInt128()
                    decodedValues.append("UInt128(High: \(uint128.high), Low: \(uint128.low))")
                } else if reader.remainingBytes >= 8 {
                    // Try to read as UInt64
                    let uint64 = try reader.readUInt64()
                    decodedValues.append("UInt64(\(uint64))")
                } else if reader.remainingBytes >= 4 {
                    // Try to read as UInt32
                    let uint32 = try reader.readUInt32()
                    decodedValues.append("UInt32(\(uint32))")
                } else if reader.remainingBytes >= 2 {
                    // Try to read as UInt16
                    let uint16 = try reader.readUInt16()
                    decodedValues.append("UInt16(\(uint16))")
                } else if reader.remainingBytes >= 1 {
                    // Try to read as UInt8
                    let uint8 = try reader.readUInt8()
                    decodedValues.append("UInt8(\(uint8))")
                }
            }
            
            return .success(decodedValues)
            
        } catch {
            return .failure(error)
        }
    }
    
    /// Set to true to enable hex viewing of messages
    private static var DEBUG_HEX_VIEW: Bool { true }
    
    /// Display data in hexadecimal format (16 bytes per line with offsets)
    private static func printHexData(_ data: Data) {
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

/// Result type for BSATN message processing
enum BSATNMessageResult {
    case success([String])  // Successfully decoded values
    case failure(Error)     // Decoding error
}