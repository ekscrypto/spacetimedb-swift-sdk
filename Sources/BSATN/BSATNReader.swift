import Foundation

/// Utility class for reading BSATN-encoded data
public class BSATNReader {
    private let data: Data
    private var offset: Int = 0
    
    public init(data: Data) {
        self.data = data
    }
    
    /// Read a specified number of bytes
    public func readBytes(_ count: Int) throws -> Data {
        guard offset + count <= data.count else {
            throw BSATNError.insufficientData
        }
        
        let result = data.subdata(in: offset..<(offset + count))
        offset += count
        return result
    }
    
    /// Read a UInt8 value
    public func readUInt8() throws -> UInt8 {
        let bytes = try readBytes(1)
        return bytes[0]
    }
    
    /// Read a UInt16 value (little-endian)
    public func readUInt16() throws -> UInt16 {
        let bytes = try readBytes(2)
        return bytes.withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
    }
    
    /// Read a UInt32 value (little-endian)
    public func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(4)
        return bytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }
    
    /// Read a UInt64 value (little-endian)
    public func readUInt64() throws -> UInt64 {
        let bytes = try readBytes(8)
        return bytes.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
    }
    
    /// Read a UInt128 value (little-endian)
    public func readUInt128() throws -> UInt128 {
        let bytes = try readBytes(16)
        return try UInt128.fromBSATN(bytes)
    }
    
    /// Read an Int8 value
    public func readInt8() throws -> Int8 {
        let bytes = try readBytes(1)
        return Int8(bitPattern: bytes[0])
    }
    
    /// Read an Int16 value (little-endian)
    public func readInt16() throws -> Int16 {
        let bytes = try readBytes(2)
        let uintValue = bytes.withUnsafeBytes { $0.load(as: UInt16.self) }
        return Int16(bitPattern: uintValue.littleEndian)
    }
    
    /// Read an Int32 value (little-endian)
    public func readInt32() throws -> Int32 {
        let bytes = try readBytes(4)
        let uintValue = bytes.withUnsafeBytes { $0.load(as: UInt32.self) }
        return Int32(bitPattern: uintValue.littleEndian)
    }
    
    /// Read an Int64 value (little-endian)
    public func readInt64() throws -> Int64 {
        let bytes = try readBytes(8)
        let uintValue = bytes.withUnsafeBytes { $0.load(as: UInt64.self) }
        return Int64(bitPattern: uintValue.littleEndian)
    }
    
    /// Read a Float32 value (little-endian)
    public func readFloat32() throws -> Float {
        let bytes = try readBytes(4)
        let bitPattern = bytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        return Float(bitPattern: bitPattern)
    }
    
    /// Read a Float64 value (little-endian)
    public func readFloat64() throws -> Double {
        let bytes = try readBytes(8)
        let bitPattern = bytes.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
        return Double(bitPattern: bitPattern)
    }
    
    /// Read a boolean value
    public func readBool() throws -> Bool {
        let byte = try readUInt8()
        switch byte {
        case 0: return false
        case 1: return true
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], 
                                    debugDescription: "Invalid boolean value: \(byte)")
            )
        }
    }
    
    /// Read a string prefixed with a UInt32 length
    public func readString() throws -> String {
        let length = try readUInt32()
        let stringData = try readBytes(Int(length))
        guard let string = String(data: stringData, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], 
                                    debugDescription: "Invalid UTF-8 data for string")
            )
        }
        return string
    }
    
    /// Read an array with UInt32 count prefix
    public func readArray(elementReader: () throws -> AlgebraicValue) throws -> [AlgebraicValue] {
        let count = try readUInt32()
        var elements: [AlgebraicValue] = []
        for _ in 0..<count {
            elements.append(try elementReader())
        }
        return elements
    }
    
    /// Read a product value (concatenated field values)
    public func readProduct(fieldReaders: [() throws -> AlgebraicValue]) throws -> [AlgebraicValue] {
        var fields: [AlgebraicValue] = []
        for reader in fieldReaders {
            fields.append(try reader())
        }
        return fields
    }
    
    /// Read a sum value (tag + variant data)
    public func readSum(variantReaders: [UInt8: () throws -> AlgebraicValue?]) throws -> (tag: UInt8, value: AlgebraicValue?) {
        let tag = try readUInt8()
        let value = try variantReaders[tag]?()
        return (tag: tag, value: value)
    }
    
    /// Read any AlgebraicValue - you would specify the type expected
    public func readAlgebraicValue(as type: AlgebraicValueType) throws -> AlgebraicValue {
        switch type {
        case .bool:
            return .bool(try readBool())
        case .uint8:
            return .uint8(try readUInt8())
        case .uint16:
            return .uint16(try readUInt16())
        case .uint32:
            return .uint32(try readUInt32())
        case .uint64:
            return .uint64(try readUInt64())
        case .uint128:
            return .uint128(try readUInt128())
        case .int8:
            return .int8(try readInt8())
        case .int16:
            return .int16(try readInt16())
        case .int32:
            return .int32(try readInt32())
        case .int64:
            return .int64(try readInt64())
        case .float32:
            return .float32(try readFloat32())
        case .float64:
            return .float64(try readFloat64())
        case .string:
            return .string(try readString())
        // For complex types, you would need to provide specific readers
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], 
                                    debugDescription: "Unsupported AlgebraicValue type: \(type)")
            )
        }
    }
    
    /// Check if there's more data to read
    public var hasMoreData: Bool {
        return offset < data.count
    }
    
    /// Current reading position
    public var position: Int {
        return offset
    }
    
    /// Remaining bytes
    public var remainingBytes: Int {
        return data.count - offset
    }
}

/// Enum representing AlgebraicValue types for reading
public enum AlgebraicValueType {
    case bool
    case uint8
    case uint16
    case uint32
    case uint64
    case uint128
    case int8
    case int16
    case int32
    case int64
    case int128
    case float32
    case float64
    case string
    case array
    case product
    case sum
}