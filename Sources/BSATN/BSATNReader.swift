import Foundation

/// Utility class for reading BSATN-encoded data
public class BSATNReader {
    private let bytes: ContiguousArray<UInt8>
    private var offset: Int = 0
    
    public init(data: Data) {
        bytes = ContiguousArray(data)
    }
    
    /// Read a specified number of bytes
    public func readBytes(_ count: Int) throws -> ArraySlice<UInt8> {
        print(">> \(#function), offset: \(offset), count: \(count), total: \(bytes.count)")
        guard offset + count <= bytes.count else {
            throw BSATNError.insufficientData
        }

        defer {
            offset += count
        }
        return bytes[offset..<(offset + count)]
    }

    func read<T: Packed>() throws -> T {
        print(">> \(#function).\(#line) \(T.self)")
        let slice = try readBytes(MemoryLayout<T>.size)
        let value: T = try slice.unpacked()
        print(">> \(#function).\(#line) \(T.self) -> \(value)")
        return value
    }

    /// Read a boolean value
    public func readBool() throws -> Bool {
        let byte: UInt8 = try read()
        return byte != 0
    }
    
    /// Read a string prefixed with a UInt32 length
    public func readString() throws -> String {
        print(">> \(#function).\(#line)")
        let length: UInt32 = try read()
        print(">> \(#function).\(#line)")
        let stringData = try readBytes(Int(length))
        print(">> \(#function).\(#line)")
        guard let string = String(data: Data(stringData), encoding: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], 
                                    debugDescription: "Invalid UTF-8 data for string")
            )
        }
        print(">> \(#function).\(#line) -> \(string)")
        return string
    }
    
    /// Read an array with UInt32 count prefix
    public func readArray(elementReader: () throws -> AlgebraicValue) throws -> [AlgebraicValue] {
        print(">> \(#function).\(#line)")
        let count: UInt32 = try read()
        var elements: [AlgebraicValue] = []
        for _ in 0..<count {
            print(">> \(#function).\(#line)")
            elements.append(try elementReader())
        }
        print(">> \(#function).\(#line)")
        return elements
    }
    
    /// Read a product value (concatenated field values)
    public func readProduct(definition valueTypes: [AlgebraicValueType]) throws -> [AlgebraicValue] {
        print(">> \(#function).\(#line) \(valueTypes)")
        var values: [AlgebraicValue] = []
        for valueType in valueTypes {
            print(">> \(#function).\(#line)")
            let value = try readAlgebraicValue(as: valueType)
            values.append(value)
        }
        print(">> \(#function).\(#line)")
        return values
    }
    
    /// Read a sum value (tag + variant data)
    public func readSum(variantReaders: [UInt8: () throws -> AlgebraicValue?]) throws -> (tag: UInt8, value: AlgebraicValue?) {
        let tag: UInt8 = try read()
        let value = try variantReaders[tag]?()
        return (tag: tag, value: value)
    }
    
    /// Read any AlgebraicValue - you would specify the type expected
    public func readAlgebraicValue(as type: AlgebraicValueType) throws -> AlgebraicValue {
        switch type {
        case .bool:
            return .bool(try read())
        case .uint8:
            return .uint8(try read())
        case .uint16:
            return .uint16(try read())
        case .uint32:
            return .uint32(try read())
        case .uint64:
            return .uint64(try read())
        case .uint128:
            return .uint128(try read())
        case .uint256:
            return .uint256(try read())
        case .int8:
            return .int8(try read())
        case .int16:
            return .int16(try read())
        case .int32:
            return .int32(try read())
        case .int64:
            return .int64(try read())
        case .int128:
            return .int128(try read())
        case .int256:
            return .int256(try read())
        case .float32:
            return .float32(try read())
        case .float64:
            return .float64(try read())
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
        return offset < bytes.count
    }
    
    /// Current reading position
    public var position: Int {
        return offset
    }
    
    /// Remaining bytes
    public var remainingBytes: Int {
        return bytes.count - offset
    }
}

/// Enum representing AlgebraicValue types for reading
public enum AlgebraicValueType: Sendable {
    case bool
    case uint8
    case uint16
    case uint32
    case uint64
    case uint128
    case uint256
    case int8
    case int16
    case int32
    case int64
    case int128
    case int256
    case float32
    case float64
    case string
    case array(ArrayModel)
    case product(ProductModel)
    case sum
}
