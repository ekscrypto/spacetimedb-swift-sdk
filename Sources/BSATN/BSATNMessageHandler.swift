import Foundation

/// Handler for processing BSATN-encoded messages from SpacetimeDB
public final class BSATNMessageHandler {
    let supportedTags: [UInt8: ProductModel]

    public init(supportedTags: [UInt8 : ProductModel]) {
        self.supportedTags = supportedTags
    }

    /// Process a BSATN message and attempt to decode it
    public func processMessage(_ data: Data) throws -> DecodedMessage {
        let reader = BSATNReader(data: data)
        guard let compression = Compression(rawValue: try reader.read()),
              compression == .uncompressed
        else {
            throw BSATNError.notImplemented
        }

        let tag: UInt8 = try reader.read()
        guard let model = supportedTags[tag] else {
            throw BSATNError.unsupportedTag(tag)
        }

        let values = try reader.readProduct(definition: model.definition)
        return DecodedMessage(tag: tag, values: values)
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

public struct DecodedMessage {
    public let tag: UInt8
    public let values: [AlgebraicValue]
}
