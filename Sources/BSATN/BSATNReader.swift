import Foundation

/// Utility class for reading BSATN-encoded data
public class BSATNReader {
    private let bytes: ContiguousArray<UInt8>
    private var offset: Int = 0
    private let printDebug: ((String) -> Void)?
    
    public var currentOffset: Int {
        return offset
    }
    
    public var isDebugEnabled: Bool {
        return printDebug != nil
    }
    
    public init(data: Data, debugEnabled: Bool = false) {
        bytes = ContiguousArray(data)
        self.printDebug = debugEnabled ? { print($0) } : nil
    }
    
    /// Read a specified number of bytes
    public func readBytes(_ count: Int) throws -> ArraySlice<UInt8> {
        printDebug?(String(format: ">> %@, offset: 0x%04X, count: %d, total: %d (0x%X)", "\(#function)", offset, count, bytes.count, bytes.count))
        guard offset + count <= bytes.count else {
            throw BSATNError.insufficientData
        }

        defer {
            offset += count
        }
        return bytes[offset..<(offset + count)]
    }

    public func read<T: Packed>() throws -> T {
        printDebug?(">> \(#function).\(#line) \(T.self)")
        let slice = try readBytes(MemoryLayout<T>.size)
        let value: T = try slice.unpacked()
        printDebug?(">> \(#function).\(#line) \(T.self) -> \(value)")
        return value
    }
    
    /// Returns all remaining data from the current offset
    public func remainingData() -> Data {
        return Data(bytes[offset..<bytes.count])
    }

    /// Read a boolean value
    public func readBool() throws -> Bool {
        let byte: UInt8 = try read()
        return byte != 0
    }
    
    /// Read a string prefixed with a UInt32 length
    public func readString() throws -> String {
        printDebug?(">> \(#function).\(#line)")
        let length: UInt32 = try read()
        printDebug?(">>> Read string of \(length) bytes")
        let stringData = try readBytes(Int(length))
        printDebug?(">> \(#function).\(#line)")
        guard let string = String(data: Data(stringData), encoding: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], 
                                    debugDescription: "Invalid UTF-8 data for string")
            )
        }
        printDebug?(">>> STRING: \(string)")
        return string
    }
    
    /// Read an array with UInt32 count prefix
    public func readArray(elementReader: () throws -> AlgebraicValue) throws -> [AlgebraicValue] {
        printDebug?(">> \(#function).\(#line)")
        let count: UInt32 = try read()
        var elements: [AlgebraicValue] = []
        for _ in 0..<count {
            printDebug?(">> \(#function).\(#line)")
            elements.append(try elementReader())
        }
        printDebug?(">> \(#function).\(#line)")
        return elements
    }
    
    /// Read a product value (concatenated field values)
    public func readProduct(definition valueTypes: [AlgebraicValueType]) throws -> [AlgebraicValue] {
        printDebug?(">> \(#function).\(#line) \(valueTypes)")
        var values: [AlgebraicValue] = []
        for valueType in valueTypes {
            printDebug?(">> \(#function).\(#line)")
            let value = try readAlgebraicValue(as: valueType)
            values.append(value)
        }
        printDebug?(">> \(#function).\(#line)")
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
        printDebug?(">>> \(#line) \(type)")
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
        case .array(let arrayModel):
            let baseType = arrayModel.definition
            let count: UInt32 = try read()
            printDebug?("Attempting to decode \(count) \(arrayModel)")
            var values: [AlgebraicValue] = []
            for _ in 0..<count {
                printDebug?(">>> \(#line)")
                values.append(try readAlgebraicValue(as: baseType))
            }
            return .array(values)
        case .product(let model):
            var values: [AlgebraicValue] = []
            for field in model.definition {
                values.append(try readAlgebraicValue(as: field))
            }
            return .product(values)
        case .sum(_):
            // Read the tag
            let tag: UInt8 = try read()
            
            // For sum types, we need to capture the raw bytes of the variant data
            // Since we don't know the structure, we need context-specific handling
            // For optional types: tag 0 = Some (has data), tag 1 = None (no data)
            
            // Save current position
            let startOffset = offset
            
            // Try to determine how much data to read based on tag
            // This is a heuristic approach for optional string types
            if tag == 1 {
                // None variant - no data
                return .sum(tag: tag, value: Data())
            } else {
                // Some variant or other - need to capture the variant's data
                // For optional string, the data should be a string
                // Try to read it as a string and capture the raw bytes
                do {
                    // Capture the starting position
                    let startPos = offset
                    // Read string length (UInt32 = 4 bytes)
                    let length: UInt32 = try read()
                    // Total size: 4 bytes (UInt32 length) + string bytes
                    let totalSize = 4 + Int(length)
                    
                    // Reset to start and read all bytes at once
                    offset = startPos
                    let rawData = try readBytes(totalSize)
                    return .sum(tag: tag, value: Data(rawData))
                } catch {
                    // If reading as string fails, reset and return empty
                    offset = startOffset
                    return .sum(tag: tag, value: Data())
                }
            }
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
    
    /// Skip forward by the specified number of bytes
    public func skip(_ count: Int) throws {
        guard offset + count <= bytes.count else {
            throw BSATNError.insufficientData
        }
        offset += count
    }
    
    /// Read an optional value
    public func readOptional<T>(readValue: () throws -> T) throws -> T? {
        let tag: UInt8 = try read()
        switch tag {
        case 0:
            // Some case - read the value
            return try readValue()
        case 1:
            // None case
            return nil
        default:
            throw BSATNError.unsupportedTag(tag)
        }
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
    case sum(SumModel)
}