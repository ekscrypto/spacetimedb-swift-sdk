import Testing
import Foundation
@testable import BSATN

@Suite("BSATN Tests")
struct BSATNTests {

    // MARK: - Basic Type Tests

    @Test("Bool encoding and decoding")
    func boolEncoding() throws {
        let writer = BSATNWriter()
        writer.write(true)
        writer.write(false)
        let data = writer.finalize()

        #expect(data.count == 2)
        #expect(data[0] == 0x01) // true
        #expect(data[1] == 0x00) // false

        // Test decoding
        let reader = BSATNReader(data: data)
        let value1: Bool = try reader.read()
        let value2: Bool = try reader.read()

        #expect(value1 == true)
        #expect(value2 == false)
    }

    @Test("UInt8 encoding and decoding")
    func uint8Encoding() throws {
        let writer = BSATNWriter()
        writer.write(UInt8(0))
        writer.write(UInt8(42))
        writer.write(UInt8(255))
        let data = writer.finalize()

        #expect(data.count == 3)

        let reader = BSATNReader(data: data)
        #expect(try reader.read() as UInt8 == 0)
        #expect(try reader.read() as UInt8 == 42)
        #expect(try reader.read() as UInt8 == 255)
    }

    @Test("UInt32 encoding and decoding")
    func uint32Encoding() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(0x12345678))
        let data = writer.finalize()

        #expect(data.count == 4)
        // Little-endian encoding
        #expect(data[0] == 0x78)
        #expect(data[1] == 0x56)
        #expect(data[2] == 0x34)
        #expect(data[3] == 0x12)

        let reader = BSATNReader(data: data)
        #expect(try reader.read() as UInt32 == 0x12345678)
    }

    @Test func uint64Encoding() throws {
        let writer = BSATNWriter()
        writer.write(UInt64(0x123456789ABCDEF0))
        let data = writer.finalize()

        #expect(data.count == 8)

        let reader = BSATNReader(data: data)
        #expect(try reader.read() as UInt64 == 0x123456789ABCDEF0)
    }

    @Test func int32Encoding() throws {
        let writer = BSATNWriter()
        writer.write(Int32(-1))
        writer.write(Int32(42))
        writer.write(Int32.min)
        writer.write(Int32.max)
        let data = writer.finalize()

        let reader = BSATNReader(data: data)
        #expect(try reader.read() as Int32 == -1)
        #expect(try reader.read() as Int32 == 42)
        #expect(try reader.read() as Int32 == Int32.min)
        #expect(try reader.read() as Int32 == Int32.max)
    }

    @Test func stringEncoding() throws {
        let writer = BSATNWriter()
        try writer.write("")
        try writer.write("Hello")
        try writer.write("Hello, world!")
        try writer.write("🚀 Unicode!")
        let data = writer.finalize()

        let reader = BSATNReader(data: data)
        #expect(try reader.readString() == "")
        #expect(try reader.readString() == "Hello")
        #expect(try reader.readString() == "Hello, world!")
        #expect(try reader.readString() == "🚀 Unicode!")
    }

    @Test func uint256Encoding() throws {
        let value = UInt256(u0: 0x0123456789ABCDEF, u1: 0xFEDCBA9876543210,
                           u2: 0x1111111111111111, u3: 0x2222222222222222)

        let writer = BSATNWriter()
        writer.write(value)
        let data = writer.finalize()

        #expect(data.count == 32)

        let reader = BSATNReader(data: data)
        let decoded: UInt256 = try reader.read()

        #expect(decoded.u0 == value.u0)
        #expect(decoded.u1 == value.u1)
        #expect(decoded.u2 == value.u2)
        #expect(decoded.u3 == value.u3)
    }

    // MARK: - AlgebraicValue Tests

    @Test func algebraicValueBasicTypes() throws {
        let writer = BSATNWriter()
        try writer.writeAlgebraicValue(.bool(true))
        try writer.writeAlgebraicValue(.uint8(42))
        try writer.writeAlgebraicValue(.uint32(12345))
        try writer.writeAlgebraicValue(.string("test"))
        let data = writer.finalize()

        let reader = BSATNReader(data: data)

        let boolValue = try reader.readAlgebraicValue(as: .bool)
        #expect(boolValue == .bool(true))

        let uint8Value = try reader.readAlgebraicValue(as: .uint8)
        #expect(uint8Value == .uint8(42))

        let uint32Value = try reader.readAlgebraicValue(as: .uint32)
        #expect(uint32Value == .uint32(12345))

        let stringValue = try reader.readAlgebraicValue(as: .string)
        #expect(stringValue == .string("test"))
    }

    @Test func arrayEncoding() throws {
        let writer = BSATNWriter()
        let array: AlgebraicValue = .array([
            .uint32(1),
            .uint32(2),
            .uint32(3)
        ])
        try writer.writeAlgebraicValue(array)
        let data = writer.finalize()

        let reader = BSATNReader(data: data)

        // Define an array model for uint32
        struct UInt32ArrayModel: ArrayModel {
            var definition: AlgebraicValueType { .uint32 }
        }

        let decoded = try reader.readAlgebraicValue(as: .array(UInt32ArrayModel()))

        guard case .array(let elements) = decoded else {
            Issue.record("Expected array")
            return
        }

        #expect(elements.count == 3)
        #expect(elements[0] == .uint32(1))
        #expect(elements[1] == .uint32(2))
        #expect(elements[2] == .uint32(3))
    }

    @Test func productEncoding() throws {
        // Create a simple product (like a struct with two fields)
        struct TestProduct: ProductModel {
            var definition: [AlgebraicValueType] { [
                .uint32,
                .string
            ]}
        }

        let writer = BSATNWriter()
        let product: AlgebraicValue = .product([
            .uint32(42),
            .string("answer")
        ])
        try writer.writeAlgebraicValue(product)
        let data = writer.finalize()

        let reader = BSATNReader(data: data)
        let decoded = try reader.readAlgebraicValue(as: .product(TestProduct()))

        guard case .product(let fields) = decoded else {
            Issue.record("Expected product")
            return
        }

        #expect(fields.count == 2)
        #expect(fields[0] == .uint32(42))
        #expect(fields[1] == .string("answer"))
    }

    @Test func optionTypeEncoding() throws {
        let writer = BSATNWriter()

        // Write Some("hello")
        writer.write(UInt8(0)) // tag 0 = Some
        try writer.write("hello")

        // Write None
        writer.write(UInt8(1)) // tag 1 = None

        let data = writer.finalize()

        let reader = BSATNReader(data: data)

        // Read Some("hello")
        let someValue = try reader.readOptional { try reader.readString() }
        #expect(someValue == "hello")

        // Read None
        let noneValue = try reader.readOptional { try reader.readString() }
        #expect(noneValue == nil)
    }

    // MARK: - Round-trip Tests

    @Test func roundTripComplexStructure() throws {
        // Simulate a UserRow-like structure
        struct UserLike: ProductModel {
            var definition: [AlgebraicValueType] { [
                .uint256,
                .sum(OptionModel(.string)),
                .bool
            ]}
        }

        let identity = UInt256(u0: 1, u1: 2, u2: 3, u3: 0xC200)

        // Test with Some(name)
        let writer1 = BSATNWriter()
        try writer1.writeAlgebraicValue(.product([
            .uint256(identity),
            .sum(tag: 0, value: .string("Alice")),
            .bool(true)
        ]))
        let data1 = writer1.finalize()

        let reader1 = BSATNReader(data: data1)
        let decoded1 = try reader1.readAlgebraicValue(as: .product(UserLike()))

        guard case .product(let fields1) = decoded1 else {
            Issue.record("Expected product")
            return
        }

        #expect(fields1[0] == .uint256(identity))
        guard case .sum(let tag1, let nameValue1) = fields1[1] else {
            Issue.record("Expected sum for optional")
            return
        }
        #expect(tag1 == 0) // Some
        guard let nameValue1 = nameValue1, case .string(let name1) = nameValue1 else {
            Issue.record("Expected string value for Some variant")
            return
        }
        #expect(name1 == "Alice")
        #expect(fields1[2] == .bool(true))

        // Test with None
        let writer2 = BSATNWriter()
        try writer2.writeAlgebraicValue(.product([
            .uint256(identity),
            .sum(tag: 1, value: nil), // None
            .bool(false)
        ]))
        let data2 = writer2.finalize()

        let reader2 = BSATNReader(data: data2)
        let decoded2 = try reader2.readAlgebraicValue(as: .product(UserLike()))

        guard case .product(let fields2) = decoded2 else {
            Issue.record("Expected product")
            return
        }

        guard case .sum(let tag2, let nameValue2) = fields2[1] else {
            Issue.record("Expected sum for optional")
            return
        }
        #expect(tag2 == 1) // None
        #expect(nameValue2 == nil)
    }

    @Test func messageRowRoundTrip() throws {
        // Simulate a MessageRow structure
        struct MessageLike: ProductModel {
            var definition: [AlgebraicValueType] { [
                .uint256,  // sender
                .uint64,   // timestamp
                .string    // text
            ]}
        }

        let sender = UInt256(u0: 0x76, u1: 0x1F9285C4D2A41830,
                            u2: 0x27BAD7B8903E7B6A, u3: 0x0E12A6DED2A483EE)
        let timestamp = UInt64(1754750460809252)
        let text = "Hello, world!"

        let writer = BSATNWriter()
        try writer.writeAlgebraicValue(.product([
            .uint256(sender),
            .uint64(timestamp),
            .string(text)
        ]))
        let data = writer.finalize()

        let reader = BSATNReader(data: data)
        let decoded = try reader.readAlgebraicValue(as: .product(MessageLike()))

        guard case .product(let fields) = decoded else {
            Issue.record("Expected product")
            return
        }

        #expect(fields[0] == .uint256(sender))
        #expect(fields[1] == .uint64(timestamp))
        #expect(fields[2] == .string(text))
    }

    // MARK: - Error Handling Tests

    @Test func insufficientDataError() throws {
        let data = Data([0x01]) // Only 1 byte
        let reader = BSATNReader(data: data)

        // Try to read a UInt32 (needs 4 bytes)
        #expect(throws: BSATNError.insufficientData) {
            _ = try reader.read() as UInt32
        }
    }

    @Test func stringWithInvalidUTF8() throws {
        let writer = BSATNWriter()
        // Write string length
        writer.write(UInt32(4))
        // Write invalid UTF-8 bytes
        writer.writeBytes(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        let data = writer.finalize()

        let reader = BSATNReader(data: data)
        #expect(throws: (any Error).self) {
            _ = try reader.readString()
        }
    }

    // MARK: - Additional Edge Case Tests

    @Test func emptyArray() throws {
        let writer = BSATNWriter()
        let array: AlgebraicValue = .array([])
        try writer.writeAlgebraicValue(array)
        let data = writer.finalize()

        let reader = BSATNReader(data: data)

        struct EmptyArrayModel: ArrayModel {
            var definition: AlgebraicValueType { .uint32 }
        }

        let decoded = try reader.readAlgebraicValue(as: .array(EmptyArrayModel()))

        guard case .array(let elements) = decoded else {
            Issue.record("Expected array")
            return
        }

        #expect(elements.count == 0)
    }

    @Test func largeArray() throws {
        let writer = BSATNWriter()
        var elements: [AlgebraicValue] = []
        for i in 0..<1000 {
            elements.append(.uint32(UInt32(i)))
        }
        let array: AlgebraicValue = .array(elements)
        try writer.writeAlgebraicValue(array)
        let data = writer.finalize()

        let reader = BSATNReader(data: data)

        struct UInt32ArrayModel: ArrayModel {
            var definition: AlgebraicValueType { .uint32 }
        }

        let decoded = try reader.readAlgebraicValue(as: .array(UInt32ArrayModel()))

        guard case .array(let decodedElements) = decoded else {
            Issue.record("Expected array")
            return
        }

        #expect(decodedElements.count == 1000)
        for i in 0..<1000 {
            #expect(decodedElements[i] == .uint32(UInt32(i)))
        }
    }

    @Test func nestedArrays() throws {
        // Test array of arrays
        struct InnerArrayModel: ArrayModel {
            var definition: AlgebraicValueType { .uint8 }
        }

        struct OuterArrayModel: ArrayModel {
            var definition: AlgebraicValueType { .array(InnerArrayModel()) }
        }

        let writer = BSATNWriter()
        let innerArray1: AlgebraicValue = .array([.uint8(1), .uint8(2)])
        let innerArray2: AlgebraicValue = .array([.uint8(3), .uint8(4)])
        let outerArray: AlgebraicValue = .array([innerArray1, innerArray2])

        try writer.writeAlgebraicValue(outerArray)
        let data = writer.finalize()

        let reader = BSATNReader(data: data)
        let decoded = try reader.readAlgebraicValue(as: .array(OuterArrayModel()))

        guard case .array(let outer) = decoded else {
            Issue.record("Expected outer array")
            return
        }

        #expect(outer.count == 2)

        guard case .array(let inner1) = outer[0] else {
            Issue.record("Expected inner array 1")
            return
        }
        #expect(inner1 == [.uint8(1), .uint8(2)])

        guard case .array(let inner2) = outer[1] else {
            Issue.record("Expected inner array 2")
            return
        }
        #expect(inner2 == [.uint8(3), .uint8(4)])
    }

    @Test func int256Encoding() throws {
        let value = Int256(u0: 0x0123456789ABCDEF, u1: 0xFEDCBA9876543210,
                          u2: 0x1111111111111111, u3: 0x2222222222222222)

        let writer = BSATNWriter()
        writer.write(value)
        let data = writer.finalize()

        #expect(data.count == 32)

        // Read it back
        let reader = BSATNReader(data: data)
        let decoded: Int256 = try reader.read()

        #expect(decoded == value)
        #expect(decoded.u0 == 0x0123456789ABCDEF)
        #expect(decoded.u1 == 0xFEDCBA9876543210)
        #expect(decoded.u2 == 0x1111111111111111)
        #expect(decoded.u3 == 0x2222222222222222)
    }

    @Test func int256CodableEncoding() throws {
        let value = Int256(u0: 0x0123456789ABCDEF, u1: 0xFEDCBA9876543210,
                          u2: 0xAAAAAAAAAAAAAAAA, u3: 0xBBBBBBBBBBBBBBBB)

        // Test JSON encoding
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(value)
        let jsonString = String(data: jsonData, encoding: .utf8)

        // Should encode as hex string (lowercase)
        #expect(jsonString == "\"bbbbbbbbbbbbbbbbaaaaaaaaaaaaaaaafedcba98765432100123456789abcdef\"")

        // Test JSON decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Int256.self, from: jsonData)
        #expect(decoded == value)
    }

    @Test func int256AlgebraicValue() throws {
        let value = Int256(u0: 0xDEADBEEF, u1: 0xCAFEBABE, u2: 0, u3: 0)

        let writer = BSATNWriter()
        try writer.writeAlgebraicValue(.int256(value))
        let data = writer.finalize()

        let reader = BSATNReader(data: data)
        let decoded = try reader.readAlgebraicValue(as: .int256)

        guard case .int256(let decodedValue) = decoded else {
            Issue.record("Expected int256")
            return
        }

        #expect(decodedValue == value)
    }

    @Test func int128Encoding() throws {
        let value = Int128(u0: 0x0123456789ABCDEF, u1: 0xFEDCBA9876543210)

        let writer = BSATNWriter()
        writer.write(value)
        let data = writer.finalize()

        #expect(data.count == 16)

        let reader = BSATNReader(data: data)
        let decoded: Int128 = try reader.read()

        #expect(decoded.u0 == value.u0)
        #expect(decoded.u1 == value.u1)
    }

    @Test func float32Encoding() throws {
        let writer = BSATNWriter()
        writer.write(Float32(3.14159))
        writer.write(Float32.infinity)
        writer.write(Float32.nan)
        writer.write(Float32(-0.0))
        let data = writer.finalize()

        let reader = BSATNReader(data: data)
        #expect(try reader.read() as Float32 == Float32(3.14159))
        #expect(try reader.read() as Float32 == Float32.infinity)
        #expect((try reader.read() as Float32).isNaN)
        #expect(try reader.read() as Float32 == Float32(-0.0))
    }

    @Test func float64Encoding() throws {
        let writer = BSATNWriter()
        writer.write(Float64(2.718281828459045))
        writer.write(Float64.infinity)
        writer.write(-Float64.infinity)
        writer.write(Float64.nan)
        let data = writer.finalize()

        let reader = BSATNReader(data: data)
        #expect(try reader.read() as Float64 == Float64(2.718281828459045))
        #expect(try reader.read() as Float64 == Float64.infinity)
        #expect(try reader.read() as Float64 == -Float64.infinity)
        #expect((try reader.read() as Float64).isNaN)
    }

    @Test func multipleOptionals() throws {
        // Test a product with multiple optional string fields
        // Note: The current BSATNReader implementation assumes sum types with tag 0 contain string data
        struct MultiOptionalProduct: ProductModel {
            var definition: [AlgebraicValueType] { [
                .sum(OptionModel(.string)),
                .sum(OptionModel(.string)),
                .sum(OptionModel(.string))
            ]}
        }

        // Test all combinations
        let testCases: [(UInt8, AlgebraicValue?, UInt8, AlgebraicValue?, UInt8, AlgebraicValue?)] = [
            // All Some
            (0, .string("first"), 0, .string("test"), 0, .string("third")),
            // All None
            (1, nil, 1, nil, 1, nil),
            // Mixed
            (0, .string("value"), 1, nil, 0, .string("last"))
        ]

        for testCase in testCases {
            let writer = BSATNWriter()
            try writer.writeAlgebraicValue(.product([
                .sum(tag: testCase.0, value: testCase.1),
                .sum(tag: testCase.2, value: testCase.3),
                .sum(tag: testCase.4, value: testCase.5)
            ]))
            let data = writer.finalize()

            let reader = BSATNReader(data: data)
            let decoded = try reader.readAlgebraicValue(as: .product(MultiOptionalProduct()))

            guard case .product(let fields) = decoded else {
                Issue.record("Expected product")
                continue
            }

            #expect(fields.count == 3)

            // Verify each field
            guard case .sum(let tag1, let value1) = fields[0] else {
                Issue.record("Expected sum at field 0")
                continue
            }
            #expect(tag1 == testCase.0)
            #expect(value1 == testCase.1)

            guard case .sum(let tag2, let value2) = fields[1] else {
                Issue.record("Expected sum at field 1")
                continue
            }
            #expect(tag2 == testCase.2)
            #expect(value2 == testCase.3)

            guard case .sum(let tag3, let value3) = fields[2] else {
                Issue.record("Expected sum at field 2")
                continue
            }
            #expect(tag3 == testCase.4)
            #expect(value3 == testCase.5)
        }
    }

    @Test func writerClearAndReuse() throws {
        let writer = BSATNWriter()

        // Write some data
        writer.write(UInt32(123))
        let data1 = writer.finalize()
        #expect(data1.count == 4)

        // Write more data (writer should be clear after finalize)
        writer.write(UInt64(456))
        let data2 = writer.finalize()
        #expect(data2.count == 8)

        // Explicitly clear and write again
        writer.clear()
        writer.write(UInt8(7))
        let data3 = writer.finalize()
        #expect(data3.count == 1)

        // Verify each piece of data independently
        let reader1 = BSATNReader(data: data1)
        #expect(try reader1.read() as UInt32 == 123)

        let reader2 = BSATNReader(data: data2)
        #expect(try reader2.read() as UInt64 == 456)

        let reader3 = BSATNReader(data: data3)
        #expect(try reader3.read() as UInt8 == 7)
    }

    @Test func boundaryValues() throws {
        let writer = BSATNWriter()

        // Test boundary values for different integer types
        writer.write(UInt8.min)
        writer.write(UInt8.max)
        writer.write(UInt16.min)
        writer.write(UInt16.max)
        writer.write(UInt32.min)
        writer.write(UInt32.max)
        writer.write(UInt64.min)
        writer.write(UInt64.max)

        writer.write(Int8.min)
        writer.write(Int8.max)
        writer.write(Int16.min)
        writer.write(Int16.max)
        writer.write(Int32.min)
        writer.write(Int32.max)
        writer.write(Int64.min)
        writer.write(Int64.max)

        let data = writer.finalize()
        let reader = BSATNReader(data: data)

        #expect(try reader.read() as UInt8 == UInt8.min)
        #expect(try reader.read() as UInt8 == UInt8.max)
        #expect(try reader.read() as UInt16 == UInt16.min)
        #expect(try reader.read() as UInt16 == UInt16.max)
        #expect(try reader.read() as UInt32 == UInt32.min)
        #expect(try reader.read() as UInt32 == UInt32.max)
        #expect(try reader.read() as UInt64 == UInt64.min)
        #expect(try reader.read() as UInt64 == UInt64.max)

        #expect(try reader.read() as Int8 == Int8.min)
        #expect(try reader.read() as Int8 == Int8.max)
        #expect(try reader.read() as Int16 == Int16.min)
        #expect(try reader.read() as Int16 == Int16.max)
        #expect(try reader.read() as Int32 == Int32.min)
        #expect(try reader.read() as Int32 == Int32.max)
        #expect(try reader.read() as Int64 == Int64.min)
        #expect(try reader.read() as Int64 == Int64.max)
    }
}