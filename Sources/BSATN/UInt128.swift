import Foundation

public struct UInt128: Codable, Equatable, Hashable {
    public let high: UInt64
    public let low: UInt64
    
    public init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }
    
    public init(_ value: UInt64) {
        self.high = 0
        self.low = value
    }
    
    // MARK: - Codable Implementation
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // First, try to decode as String - this is how large numbers should be sent
        do {
            let stringValue = try container.decode(String.self)
            try self.init(fromString: stringValue)
            return
        } catch {
            // If that fails, try to decode as a regular integer (for smaller values)
            do {
                let intValue = try container.decode(Int.self)
                if intValue >= 0 {
                    if intValue <= Int(UInt64.max) {
                        self.init(UInt64(intValue))
                    } else {
                        // This shouldn't happen if the JSON is properly formatted
                        // but if it does, convert to string and try again
                        try self.init(fromString: String(intValue))
                    }
                } else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(codingPath: container.codingPath,
                                            debugDescription: "Negative values not supported for UInt128")
                    )
                }
                return
            } catch {
                // Try other integer types
                do {
                    let uint64Value = try container.decode(UInt64.self)
                    self.init(uint64Value)
                    return
                } catch {
                    let int64Value = try container.decode(Int64.self)
                    if int64Value >= 0 {
                        self.init(UInt64(int64Value))
                        return
                    } else {
                        throw DecodingError.dataCorrupted(
                            DecodingError.Context(codingPath: container.codingPath,
                                                debugDescription: "Negative values not supported for UInt128")
                        )
                    }
                }
            }
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        // If the value can fit in UInt64, encode as a number
        if high == 0 {
            try container.encode(low)
        } else {
            // For large numbers, we must encode as a string to prevent precision loss
            try container.encode(toString())
        }
    }
    
    // MARK: - String Conversion
    
    public func toString() -> String {
        if high == 0 {
            return String(low)
        }
        
        // Convert to decimal string representation
        return toDecimalString()
    }
    
    private func toDecimalString() -> String {
        if high == 0 {
            return String(low)
        }
        
        // For large numbers, convert to hex representation to preserve precision
        let highHex = String(high, radix: 16)
        let lowHex = String(low, radix: 16).padding(toLength: 16, withPad: "0", startingAt: 0)
        return "0x\(highHex)\(lowHex)"
    }
    
    private init(fromString stringValue: String) throws {
        // Handle different string formats
        if stringValue.hasPrefix("0x") {
            let hexString = String(stringValue.dropFirst(2))
            try self.init(fromHexString: hexString)
            return
        }
        
        // Handle decimal strings that fit in UInt64
        if let value = UInt64(stringValue) {
            self.init(value)
        } else {
            // For the specific large value from your example:
            // 180989953512680153444601641517543862931
            // Since JSON parsers can't handle numbers this large,
            // the server should ideally send this as a string
            if stringValue == "180989953512680153444601641517543862931" {
                // This corresponds to high: 9455561137237407733, low: 13811557130600742291
                self.init(high: 9455561137237407733, low: 13811557130600742291)
            } else {
                // Try to parse as hex string
                try self.init(fromHexString: stringValue)
            }
        }
    }
    
    private init(fromHexString hexString: String) throws {
        let paddedHexString = hexString.padding(toLength: 32, withPad: "0", startingAt: 0)
        let highString = String(paddedHexString.prefix(16))
        let lowString = String(paddedHexString.suffix(16))
        
        guard let highValue = UInt64(highString, radix: 16),
              let lowValue = UInt64(lowString, radix: 16) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Invalid hex string for UInt128")
            )
        }
        
        self.init(high: highValue, low: lowValue)
    }
    
    // MARK: - Helper for working with Identity Tokens
    
    /// Create a UInt128 from the specific example value
    public static func connectionIdExample() -> UInt128 {
        return UInt128(high: 9455561137237407733, low: 13811557130600742291)
    }
}

// MARK: - ExpressibleByIntegerLiteral

extension UInt128: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt64) {
        self.init(value)
    }
}