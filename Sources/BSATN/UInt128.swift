public struct UInt128: Equatable, Hashable, CustomStringConvertible, Codable {
    public let u0: UInt64
    public let u1: UInt64
    
    public init(u0: UInt64 = 0, u1: UInt64 = 0) {
        self.u0 = u0
        self.u1 = u1
    }
    
    public var description: String {
        let hex0 = String(format: "%016llx", u0)
        let hex1 = String(format: "%016llx", u1)
        return hex1 + hex0
    }
    
    // Custom Codable implementation to encode/decode as hex string
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hexString = try container.decode(String.self)
        
        guard hexString.count == 32 else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "UInt128 hex string must be 32 characters")
        }
        
        let startIndex = hexString.startIndex
        let u1Hex = String(hexString[startIndex..<hexString.index(startIndex, offsetBy: 16)])
        let u0Hex = String(hexString[hexString.index(startIndex, offsetBy: 16)..<hexString.index(startIndex, offsetBy: 32)])
        
        guard let u0 = UInt64(u0Hex, radix: 16),
              let u1 = UInt64(u1Hex, radix: 16) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid hex string for UInt128")
        }
        
        self.u0 = u0
        self.u1 = u1
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Encode as hex string
        try container.encode(self.description)
    }
}
