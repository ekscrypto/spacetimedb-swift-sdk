import Foundation

/// Utility class for writing BSATN-encoded data
public class BSATNWriter {
    private var data = Data()
    
    /// Initialize a new BSATNWriter
    public init() {}
    
    /// Write raw bytes
    public func writeBytes(_ bytes: Data) {
        data.append(bytes)
    }

    public func finalize() -> Data {
        let finalizedData = data
        data.removeAll()
        return finalizedData
    }

    internal func write(_ value: Packed) {
        value.appended(to: &data)
    }

    public func write(_ value: Bool) { value.appended(to: &data) }
    public func write(_ value: UInt8) { value.appended(to: &data) }
    public func write(_ value: UInt16) { value.appended(to: &data) }
    public func write(_ value: UInt32) { value.appended(to: &data) }
    public func write(_ value: UInt64) { value.appended(to: &data) }
    public func write(_ value: UInt128) { value.appended(to: &data) }
    public func write(_ value: UInt256) { value.appended(to: &data) }
    public func write(_ value: Int8) { value.appended(to: &data) }
    public func write(_ value: Int16) { value.appended(to: &data) }
    public func write(_ value: Int32) { value.appended(to: &data) }
    public func write(_ value: Int64) { value.appended(to: &data) }
    public func write(_ value: Int128) { value.appended(to: &data) }
    public func write(_ value: Int256) { value.appended(to: &data) }
    public func write(_ value: Float32) { value.appended(to: &data) }
    public func write(_ value: Float64) { value.appended(to: &data) }

    /// Write a string with UInt32 length prefix
    public func write(_ value: String) throws {
        guard let stringData = value.data(using: .utf8) else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Cannot encode string to UTF-8"))
        }
        
        write(UInt32(stringData.count))
        data.append(stringData)
    }
    
    /// Write raw data directly
    public func write(_ value: Data) {
        data.append(value)
    }
    
    /// Write a string with UInt16 length prefix (for compatibility)
    public func writeStringU16(_ value: String) throws {
        guard let stringData = value.data(using: .utf8) else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Cannot encode string to UTF-8"))
        }
        
        write(UInt16(stringData.count))
        data.append(stringData)
    }
    
    /// Write an array with UInt32 count prefix
    public func writeArray(_ array: [AlgebraicValue], elementWriter: (AlgebraicValue) throws -> Void) throws {
        write(UInt32(array.count))
        for element in array {
            try elementWriter(element)
        }
    }
    
    /// Write a product value (concatenated field values)
    public func writeProduct(fieldValues: [AlgebraicValue], fieldWriters: [(AlgebraicValue) throws -> Void]) throws {
        guard fieldValues.count == fieldWriters.count else {
            throw EncodingError.invalidValue(fieldValues, EncodingError.Context(codingPath: [], debugDescription: "Mismatch between field values and writers"))
        }
        
        for (index, value) in fieldValues.enumerated() {
            try fieldWriters[index](value)
        }
    }
    
    /// Write a sum value (tag + variant data)
    public func writeSum(tag: UInt8, value: AlgebraicValue?, variantWriter: ((AlgebraicValue) throws -> Void)?) throws {
        write(tag)
        if let value = value, let writer = variantWriter {
            try writer(value)
        }
    }
    
    /// Write any AlgebraicValue
    public func writeAlgebraicValue(_ value: AlgebraicValue) throws {
        switch value {
        case .bool(let b):
            write(b)
        case .uint8(let u):
            write(u)
        case .uint16(let u):
            write(u)
        case .uint32(let u):
            write(u)
        case .uint64(let u):
            write(u)
        case .uint128(let u):
            write(u)
        case .uint256(let u):
            write(u)
        case .int8(let i):
            write(i)
        case .int16(let i):
            write(i)
        case .int32(let i):
            write(i)
        case .int64(let i):
            write(i)
        case .int128(let i):
            write(i)
        case .int256(let i):
            write(i)
        case .float32(let f):
            write(f)
        case .float64(let d):
            write(d)
        case .string(let s):
            try write(s)
        case .array(let a):
            // Write array count and then each element
            write(UInt32(a.count))
            for element in a {
                try writeAlgebraicValue(element)
            }
        case .product(let p):
            // For products, write concatenated field values
            // This is a simplified implementation - in practice you'd have field writers
            for fieldValue in p {
                try writeAlgebraicValue(fieldValue)
            }
        case .sum(let tag, let value):
            write(tag)
            writeBytes(value)
        }
    }
    
    /// Clear the writer
    public func clear() {
        data.removeAll()
    }
}
