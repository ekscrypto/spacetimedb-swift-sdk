import Foundation
import BSATN

/// Test functions to demonstrate BSATN functionality
func runBSATNTests() {
    print("=== BSATN Test Suite ===")
    
    // Test 1: Hex viewer with sample data
    testHexViewer()
    
    // Test 2: BSATN encoding/decoding
    testBSATNEncoding()
    
    print("=== End BSATN Test Suite ===\n")
}

private func testHexViewer() {
    print("\n1. Testing Hex Viewer:")
    
    // Create sample binary data
    let sampleData = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                          0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
                          0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
                          0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0x57, 0x6F,
                          0x72, 0x6C, 0x64, 0x21]) // "Hello World!"
    
    print("Sample data in hex format:")
    printHexData(sampleData)
}

private func testBSATNEncoding() {
    print("\n2. Testing BSATN Encoding/Decoding:")
    
    // Create a complex data structure and encode it
    let writer = BSATNWriter()
    
    // Write various data types
    writer.writeBool(true)
    writer.writeUInt8(255)
    writer.writeUInt16(65535)
    writer.writeUInt32(4294967295)
    writer.writeUInt64(18446744073709551615)
    
    // Write a UInt128
    let uint128 = UInt128(high: 0x1234567890ABCDEF, low: 0xFEDCBA0987654321)
    writer.writeUInt128(uint128)
    
    // Write a string
    do {
        try writer.writeString("Hello, SpacetimeDB!")
    } catch {
        print("Error writing string: \(error)")
        return
    }
    
    let encodedData = writer.writtenData
    print("Encoded \(encodedData.count) bytes:")
    printHexData(encodedData)
    
    // Now try to decode it
    print("\nDecoding the data:")
    let result = BSATNMessageHandler.processMessage(encodedData)
    switch result {
    case .success(let values):
        print("Successfully decoded values:")
        for value in values {
            print("  \(value)")
        }
    case .failure(let error):
        print("Failed to decode: \(error)")
    }
}

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