import Foundation

/// Utility class for writing BSATN-encoded data
public class BSATNWriter {
    private var data = Data()
    
    /// Get the written data
    public var writtenData: Data {
        return data
    }
    
    /// Initialize a new BSATNWriter
    public init() {}
    
    /// Write raw bytes
    public func writeBytes(_ bytes: Data) {
        data.append(bytes)
    }
    
    /// Write a UInt8 value
    public func writeUInt8(_ value: UInt8) {
        data.append(value)
    }
    
    /// Write a UInt16 value (little-endian)
    public func writeUInt16(_ value: UInt16) {
        var leValue = value.littleEndian
        withUnsafePointer(to: &leValue) {
            data.append(Data(bytes: $0, count: MemoryLayout<UInt16>.size))
        }
    }
    
    /// Write a UInt32 value (little-endian)
    public func writeUInt32(_ value: UInt32) {
        var leValue = value.littleEndian
        withUnsafePointer(to: &leValue) {
            data.append(Data(bytes: $0, count: MemoryLayout<UInt32>.size))
        }
    }
    
    /// Write a UInt64 value (little-endian)
    public func writeUInt64(_ value: UInt64) {
        var leValue = value.littleEndian
        withUnsafePointer(to: &leValue) {
            data.append(Data(bytes: $0, count: MemoryLayout<UInt64>.size))
        }
    }
    
    /// Write a UInt128 value (little-endian)
    public func writeUInt128(_ value: UInt128) {
        data.append(value.toBSATN())
    }
    
    /// Write an Int8 value
    public func writeInt8(_ value: Int8) {
        data.append(UInt8(bitPattern: value))
    }
    
    /// Write an Int16 value (little-endian)
    public func writeInt16(_ value: Int16) {
        var leValue = value.littleEndian
        withUnsafePointer(to: &leValue) {
            data.append(Data(bytes: $0, count: MemoryLayout<Int16>.size))
        }
    }
    
    /// Write an Int32 value (little-endian)
    public func writeInt32(_ value: Int32) {
        var leValue = value.littleEndian
        withUnsafePointer(to: &leValue) {
            data.append(Data(bytes: $0, count: MemoryLayout<Int32>.size))
        }
    }
    
    /// Write an Int64 value (little-endian)
    public func writeInt64(_ value: Int64) {
        var leValue = value.littleEndian
        withUnsafePointer(to: &leValue) {
            data.append(Data(bytes: $0, count: MemoryLayout<Int64>.size))
        }
    }
    
    /// Write a Float32 value (little-endian)
    public func writeFloat32(_ value: Float) {
        var bitPattern = value.bitPattern
        var leValue = bitPattern.littleEndian
        withUnsafePointer(to: &leValue) {
            data.append(Data(bytes: $0, count: MemoryLayout<UInt32>.size))
        }
    }
    
    /// Write a Float64 value (little-endian)
    public func writeFloat64(_ value: Double) {
        var bitPattern = value.bitPattern
        var leValue = bitPattern.littleEndian
        withUnsafePointer(to: &leValue) {
            data.append(Data(bytes: $0, count: MemoryLayout<UInt64>.size))
        }
    }
    
    /// Write a boolean value
    public func writeBool(_ value: Bool) {
        data.append(value ? 1 : 0)
    }
    
    /// Write a string with UInt32 length prefix
    public func writeString(_ value: String) throws {
        guard let stringData = value.data(using: .utf8) else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Cannot encode string to UTF-8"))
        }
        
        writeUInt32(UInt32(stringData.count))
        data.append(stringData)
    }
    
    /// Write an array with UInt32 count prefix
    public func writeArray(_ array: [AlgebraicValue], elementWriter: (AlgebraicValue) throws -> Void) throws {
        writeUInt32(UInt32(array.count))
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
        writeUInt8(tag)
        if let value = value, let writer = variantWriter {
            try writer(value)
        }
    }
    
    /// Write any AlgebraicValue
    public func writeAlgebraicValue(_ value: AlgebraicValue) throws {
        switch value {
        case .bool(let b):
            writeBool(b)
        case .uint8(let u):
            writeUInt8(u)
        case .uint16(let u):
            writeUInt16(u)
        case .uint32(let u):
            writeUInt32(u)
        case .uint64(let u):
            writeUInt64(u)
        case .uint128(let u):
            writeUInt128(u)
        case .int8(let i):
            writeInt8(i)
        case .int16(let i):
            writeInt16(i)
        case .int32(let i):
            writeInt32(i)
        case .int64(let i):
            writeInt64(i)
        case .int128(let i):
            // Handle Int128 - for now just write the parts
            writeInt64(i.high)
            writeUInt64(i.low)
        case .float32(let f):
            writeFloat32(f)
        case .float64(let d):
            writeFloat64(d)
        case .string(let s):
            try writeString(s)
        case .array(let a):
            // For arrays, we need to know how to encode the elements
            // This is a simplified implementation - in practice you'd have element writers
            writeUInt32(UInt32(a.count))
            // You would need to provide specific element writers for complete implementation
            break
        case .product(let p):
            // For products, write concatenated field values
            // This is a simplified implementation - in practice you'd have field writers
            for fieldValue in p {
                try writeAlgebraicValue(fieldValue)
            }
        case .sum(let tag, let value):
            writeUInt8(tag)
            if let value = value {
                try writeAlgebraicValue(value)
            }
        }
    }
    
    /// Clear the writer
    public func clear() {
        data.removeAll()
    }
}