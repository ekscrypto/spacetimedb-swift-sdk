import Foundation

extension UInt128 {
    /// Parse a UInt128 value from BSATN binary data (16 bytes, little-endian)
    /// According to BSATN spec: bsatn(U128(x: u128)) = to_little_endian_bytes(x)
    public static func fromBSATN(_ data: Data) throws -> UInt128 {
        guard data.count == 16 else {
            throw BSATNError.invalidDataSize(expected: 16, actual: data.count)
        }
        
        // BSATN encodes UInt128 as 16 bytes in little-endian format
        // We need to extract the low 8 bytes and high 8 bytes
        
        // First 8 bytes (0-7) are the low part in little-endian
        let lowBytes = data.subdata(in: 0..<8)
        // Next 8 bytes (8-15) are the high part in little-endian
        let highBytes = data.subdata(in: 8..<16)
        
        // Convert little-endian bytes to UInt64
        let low = lowBytes.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
        let high = highBytes.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
        
        return UInt128(high: high, low: low)
    }
    
    /// Convert UInt128 to BSATN binary data (16 bytes, little-endian)
    public func toBSATN() -> Data {
        var lowLE = low.littleEndian
        var highLE = high.littleEndian
        
        var data = Data()
        withUnsafePointer(to: &lowLE) {
            data.append(Data(bytes: $0, count: MemoryLayout<UInt64>.size))
        }
        withUnsafePointer(to: &highLE) {
            data.append(Data(bytes: $0, count: MemoryLayout<UInt64>.size))
        }
        
        return data
    }
}

// MARK: - BSATN Error Types

public enum BSATNError: Error, LocalizedError {
    case invalidDataSize(expected: Int, actual: Int)
    case insufficientData
    
    public var errorDescription: String? {
        switch self {
        case .invalidDataSize(let expected, let actual):
            return "Invalid data size for UInt128. Expected \(expected) bytes, got \(actual) bytes."
        case .insufficientData:
            return "Insufficient data to decode UInt128."
        }
    }
}