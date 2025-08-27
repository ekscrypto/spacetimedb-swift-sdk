public struct UInt256: Equatable, Hashable, CustomStringConvertible, Sendable, Codable {
    public let u0: UInt64
    public let u1: UInt64
    public let u2: UInt64
    public let u3: UInt64

    public init(u0: UInt64, u1: UInt64, u2: UInt64, u3: UInt64) {
        self.u0 = u0
        self.u1 = u1
        self.u2 = u2
        self.u3 = u3
    }

    public var description: String {
        let hex0 = String(format: "%016llx", u0)
        let hex1 = String(format: "%016llx", u1)
        let hex2 = String(format: "%016llx", u2)
        let hex3 = String(format: "%016llx", u3)
        return hex3 + hex2 + hex1 + hex0
    }

    // Custom Codable implementation to encode/decode as hex string
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hexString = try container.decode(String.self)

        guard hexString.count == 64 else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "UInt256 hex string must be 64 characters")
        }

        let startIndex = hexString.startIndex
        let u3Hex = String(hexString[startIndex..<hexString.index(startIndex, offsetBy: 16)])
        let u2Hex = String(hexString[hexString.index(startIndex, offsetBy: 16)..<hexString.index(startIndex, offsetBy: 32)])
        let u1Hex = String(hexString[hexString.index(startIndex, offsetBy: 32)..<hexString.index(startIndex, offsetBy: 48)])
        let u0Hex = String(hexString[hexString.index(startIndex, offsetBy: 48)..<hexString.index(startIndex, offsetBy: 64)])

        guard let u0 = UInt64(u0Hex, radix: 16),
              let u1 = UInt64(u1Hex, radix: 16),
              let u2 = UInt64(u2Hex, radix: 16),
              let u3 = UInt64(u3Hex, radix: 16) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid hex string for UInt256")
        }

        self.u0 = u0
        self.u1 = u1
        self.u2 = u2
        self.u3 = u3
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Encode as hex string
        try container.encode(self.description)
    }
}
