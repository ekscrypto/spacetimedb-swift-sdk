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
        case .sum(let model):
            // Read the tag
            let tag: UInt8 = try read()
            
            // Save current position for reading variant data
            let startOffset = offset
            
            // Check if this is an Option type
            if let optionModel = model as? OptionModel {
                // Option type: tag 0 = Some, tag 1 = None
                if tag == 1 {
                    // None variant - no value
                    return .sum(tag: tag, value: nil)
                } else if tag == 0 {
                    // Some variant - recursively read the wrapped type
                    do {
                        // Read the wrapped value using its type definition
                        let wrappedValue = try readAlgebraicValue(as: optionModel.wrappedType)
                        return .sum(tag: tag, value: wrappedValue)
                    } catch {
                        // If reading fails, return None variant
                        offset = startOffset
                        throw error
                    }
                } else {
                    // Unknown tag for Option type
                    throw BSATNError.invalidSumTag(tag)
                }
            } else {
                // For non-Option sum types, we don't have enough model information
                // This is a limitation that should be addressed with proper variant models
                // For now, attempt to read as string if tag is 0, otherwise return nil
                if tag == 1 {
                    // Assume None-like variant with no value
                    return .sum(tag: tag, value: nil)
                } else {
                    // Try to read as string (current heuristic for backwards compatibility)
                    do {
                        let stringValue = try readAlgebraicValue(as: .string)
                        return .sum(tag: tag, value: stringValue)
                    } catch {
                        // If string reading fails, return nil
                        offset = startOffset
                        return .sum(tag: tag, value: nil)
                    }
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