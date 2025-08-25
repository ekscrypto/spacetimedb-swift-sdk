import XCTest
@testable import BSATN

final class BSATNTests: XCTestCase {
    
    // MARK: - Basic Type Tests
    
    func testBoolEncoding() throws {
        let writer = BSATNWriter()
        writer.write(true)
        writer.write(false)
        let data = writer.finalize()
        
        XCTAssertEqual(data.count, 2)
        XCTAssertEqual(data[0], 0x01) // true
        XCTAssertEqual(data[1], 0x00) // false
        
        // Test decoding
        let reader = BSATNReader(data: data)
        let value1: Bool = try reader.read()
        let value2: Bool = try reader.read()
        
        XCTAssertEqual(value1, true)
        XCTAssertEqual(value2, false)
    }
    
    func testUInt8Encoding() throws {
        let writer = BSATNWriter()
        writer.write(UInt8(0))
        writer.write(UInt8(42))
        writer.write(UInt8(255))
        let data = writer.finalize()
        
        XCTAssertEqual(data.count, 3)
        
        let reader = BSATNReader(data: data)
        XCTAssertEqual(try reader.read() as UInt8, 0)
        XCTAssertEqual(try reader.read() as UInt8, 42)
        XCTAssertEqual(try reader.read() as UInt8, 255)
    }
    
    func testUInt32Encoding() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(0x12345678))
        let data = writer.finalize()
        
        XCTAssertEqual(data.count, 4)
        // Little-endian encoding
        XCTAssertEqual(data[0], 0x78)
        XCTAssertEqual(data[1], 0x56)
        XCTAssertEqual(data[2], 0x34)
        XCTAssertEqual(data[3], 0x12)
        
        let reader = BSATNReader(data: data)
        XCTAssertEqual(try reader.read() as UInt32, 0x12345678)
    }
    
    func testUInt64Encoding() throws {
        let writer = BSATNWriter()
        writer.write(UInt64(0x123456789ABCDEF0))
        let data = writer.finalize()
        
        XCTAssertEqual(data.count, 8)
        
        let reader = BSATNReader(data: data)
        XCTAssertEqual(try reader.read() as UInt64, 0x123456789ABCDEF0)
    }
    
    func testInt32Encoding() throws {
        let writer = BSATNWriter()
        writer.write(Int32(-1))
        writer.write(Int32(42))
        writer.write(Int32.min)
        writer.write(Int32.max)
        let data = writer.finalize()
        
        let reader = BSATNReader(data: data)
        XCTAssertEqual(try reader.read() as Int32, -1)
        XCTAssertEqual(try reader.read() as Int32, 42)
        XCTAssertEqual(try reader.read() as Int32, Int32.min)
        XCTAssertEqual(try reader.read() as Int32, Int32.max)
    }
    
    func testStringEncoding() throws {
        let writer = BSATNWriter()
        try writer.write("")
        try writer.write("Hello")
        try writer.write("Hello, world!")
        try writer.write("🚀 Unicode!")
        let data = writer.finalize()
        
        let reader = BSATNReader(data: data)
        XCTAssertEqual(try reader.readString(), "")
        XCTAssertEqual(try reader.readString(), "Hello")
        XCTAssertEqual(try reader.readString(), "Hello, world!")
        XCTAssertEqual(try reader.readString(), "🚀 Unicode!")
    }
    
    func testUInt256Encoding() throws {
        let value = UInt256(u0: 0x0123456789ABCDEF, u1: 0xFEDCBA9876543210,
                           u2: 0x1111111111111111, u3: 0x2222222222222222)
        
        let writer = BSATNWriter()
        writer.write(value)
        let data = writer.finalize()
        
        XCTAssertEqual(data.count, 32)
        
        let reader = BSATNReader(data: data)
        let decoded: UInt256 = try reader.read()
        
        XCTAssertEqual(decoded.u0, value.u0)
        XCTAssertEqual(decoded.u1, value.u1)
        XCTAssertEqual(decoded.u2, value.u2)
        XCTAssertEqual(decoded.u3, value.u3)
    }
    
    // MARK: - AlgebraicValue Tests
    
    func testAlgebraicValueBasicTypes() throws {
        let writer = BSATNWriter()
        try writer.writeAlgebraicValue(.bool(true))
        try writer.writeAlgebraicValue(.uint8(42))
        try writer.writeAlgebraicValue(.uint32(12345))
        try writer.writeAlgebraicValue(.string("test"))
        let data = writer.finalize()
        
        let reader = BSATNReader(data: data)
        
        let boolValue = try reader.readAlgebraicValue(as: .bool)
        XCTAssertEqual(boolValue, .bool(true))
        
        let uint8Value = try reader.readAlgebraicValue(as: .uint8)
        XCTAssertEqual(uint8Value, .uint8(42))
        
        let uint32Value = try reader.readAlgebraicValue(as: .uint32)
        XCTAssertEqual(uint32Value, .uint32(12345))
        
        let stringValue = try reader.readAlgebraicValue(as: .string)
        XCTAssertEqual(stringValue, .string("test"))
    }
    
    func testArrayEncoding() throws {
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
            XCTFail("Expected array")
            return
        }
        
        XCTAssertEqual(elements.count, 3)
        XCTAssertEqual(elements[0], .uint32(1))
        XCTAssertEqual(elements[1], .uint32(2))
        XCTAssertEqual(elements[2], .uint32(3))
    }
    
    func testProductEncoding() throws {
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
            XCTFail("Expected product")
            return
        }
        
        XCTAssertEqual(fields.count, 2)
        XCTAssertEqual(fields[0], .uint32(42))
        XCTAssertEqual(fields[1], .string("answer"))
    }
    
    func testOptionTypeEncoding() throws {
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
        XCTAssertEqual(someValue, "hello")
        
        // Read None
        let noneValue = try reader.readOptional { try reader.readString() }
        XCTAssertNil(noneValue)
    }
    
    // MARK: - Round-trip Tests
    
    func testRoundTripComplexStructure() throws {
        // Simulate a UserRow-like structure
        struct UserLike: ProductModel {
            var definition: [AlgebraicValueType] { [
                .uint256,
                .option(.string),
                .bool
            ]}
        }
        
        let identity = UInt256(u0: 1, u1: 2, u2: 3, u3: 0xC200)
        
        // Test with Some(name)
        let writer1 = BSATNWriter()
        try writer1.writeAlgebraicValue(.product([
            .uint256(identity),
            .sum(tag: 0, value: {
                let w = BSATNWriter()
                try! w.write("Alice")
                return w.finalize()
            }()),
            .bool(true)
        ]))
        let data1 = writer1.finalize()
        
        let reader1 = BSATNReader(data: data1)
        let decoded1 = try reader1.readAlgebraicValue(as: .product(UserLike()))
        
        guard case .product(let fields1) = decoded1 else {
            XCTFail("Expected product")
            return
        }
        
        XCTAssertEqual(fields1[0], .uint256(identity))
        guard case .sum(let tag1, let nameData1) = fields1[1] else {
            XCTFail("Expected sum for optional")
            return
        }
        XCTAssertEqual(tag1, 0) // Some
        let nameReader = BSATNReader(data: nameData1)
        XCTAssertEqual(try nameReader.readString(), "Alice")
        XCTAssertEqual(fields1[2], .bool(true))
        
        // Test with None
        let writer2 = BSATNWriter()
        try writer2.writeAlgebraicValue(.product([
            .uint256(identity),
            .sum(tag: 1, value: Data()), // None
            .bool(false)
        ]))
        let data2 = writer2.finalize()
        
        let reader2 = BSATNReader(data: data2)
        let decoded2 = try reader2.readAlgebraicValue(as: .product(UserLike()))
        
        guard case .product(let fields2) = decoded2 else {
            XCTFail("Expected product")
            return
        }
        
        guard case .sum(let tag2, let nameData2) = fields2[1] else {
            XCTFail("Expected sum for optional")
            return
        }
        XCTAssertEqual(tag2, 1) // None
        XCTAssertEqual(nameData2.count, 0)
    }
    
    func testMessageRowRoundTrip() throws {
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
            XCTFail("Expected product")
            return
        }
        
        XCTAssertEqual(fields[0], .uint256(sender))
        XCTAssertEqual(fields[1], .uint64(timestamp))
        XCTAssertEqual(fields[2], .string(text))
    }
    
    // MARK: - Error Handling Tests
    
    func testInsufficientDataError() throws {
        let data = Data([0x01]) // Only 1 byte
        let reader = BSATNReader(data: data)
        
        // Try to read a UInt32 (needs 4 bytes)
        XCTAssertThrowsError(try reader.read() as UInt32) { error in
            guard case BSATNError.insufficientData = error else {
                XCTFail("Expected insufficientData error")
                return
            }
        }
    }
    
    func testStringWithInvalidUTF8() throws {
        let writer = BSATNWriter()
        // Write string length
        writer.write(UInt32(4))
        // Write invalid UTF-8 bytes
        writer.writeBytes(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        let data = writer.finalize()
        
        let reader = BSATNReader(data: data)
        XCTAssertThrowsError(try reader.readString()) { error in
            // BSATNReader throws a general error for invalid UTF-8
            // We'll just check that it throws an error
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Additional Edge Case Tests
    
    func testEmptyArray() throws {
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
            XCTFail("Expected array")
            return
        }
        
        XCTAssertEqual(elements.count, 0)
    }
    
    func testLargeArray() throws {
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
            XCTFail("Expected array")
            return
        }
        
        XCTAssertEqual(decodedElements.count, 1000)
        for i in 0..<1000 {
            XCTAssertEqual(decodedElements[i], .uint32(UInt32(i)))
        }
    }
    
    func testNestedArrays() throws {
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
            XCTFail("Expected outer array")
            return
        }
        
        XCTAssertEqual(outer.count, 2)
        
        guard case .array(let inner1) = outer[0] else {
            XCTFail("Expected inner array 1")
            return
        }
        XCTAssertEqual(inner1, [.uint8(1), .uint8(2)])
        
        guard case .array(let inner2) = outer[1] else {
            XCTFail("Expected inner array 2")
            return
        }
        XCTAssertEqual(inner2, [.uint8(3), .uint8(4)])
    }
    
    func testInt128Encoding() throws {
        let value = Int128(u0: 0x0123456789ABCDEF, u1: 0xFEDCBA9876543210)
        
        let writer = BSATNWriter()
        writer.write(value)
        let data = writer.finalize()
        
        XCTAssertEqual(data.count, 16)
        
        let reader = BSATNReader(data: data)
        let decoded: Int128 = try reader.read()
        
        XCTAssertEqual(decoded.u0, value.u0)
        XCTAssertEqual(decoded.u1, value.u1)
    }
    
    func testFloat32Encoding() throws {
        let writer = BSATNWriter()
        writer.write(Float32(3.14159))
        writer.write(Float32.infinity)
        writer.write(Float32.nan)
        writer.write(Float32(-0.0))
        let data = writer.finalize()
        
        let reader = BSATNReader(data: data)
        XCTAssertEqual(try reader.read() as Float32, Float32(3.14159))
        XCTAssertEqual(try reader.read() as Float32, Float32.infinity)
        XCTAssertTrue((try reader.read() as Float32).isNaN)
        XCTAssertEqual(try reader.read() as Float32, Float32(-0.0))
    }
    
    func testFloat64Encoding() throws {
        let writer = BSATNWriter()
        writer.write(Float64(2.718281828459045))
        writer.write(Float64.infinity)
        writer.write(-Float64.infinity)
        writer.write(Float64.nan)
        let data = writer.finalize()
        
        let reader = BSATNReader(data: data)
        XCTAssertEqual(try reader.read() as Float64, Float64(2.718281828459045))
        XCTAssertEqual(try reader.read() as Float64, Float64.infinity)
        XCTAssertEqual(try reader.read() as Float64, -Float64.infinity)
        XCTAssertTrue((try reader.read() as Float64).isNaN)
    }
    
    func testMultipleOptionals() throws {
        // Test a product with multiple optional fields
        struct MultiOptionalProduct: ProductModel {
            var definition: [AlgebraicValueType] { [
                .option(.uint32),
                .option(.string),
                .option(.bool)
            ]}
        }
        
        // Test all combinations
        let testCases: [(UInt8, Data, UInt8, Data, UInt8, Data)] = [
            // All Some
            (0, { let w = BSATNWriter(); w.write(UInt32(42)); return w.finalize() }(),
             0, { let w = BSATNWriter(); try! w.write("test"); return w.finalize() }(),
             0, { let w = BSATNWriter(); w.write(true); return w.finalize() }()),
            // All None
            (1, Data(), 1, Data(), 1, Data()),
            // Mixed
            (0, { let w = BSATNWriter(); w.write(UInt32(100)); return w.finalize() }(),
             1, Data(),
             0, { let w = BSATNWriter(); w.write(false); return w.finalize() }())
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
                XCTFail("Expected product")
                continue
            }
            
            XCTAssertEqual(fields.count, 3)
            
            // Verify each field
            guard case .sum(let tag1, _) = fields[0] else {
                XCTFail("Expected sum at field 0")
                continue
            }
            XCTAssertEqual(tag1, testCase.0)
            
            guard case .sum(let tag2, _) = fields[1] else {
                XCTFail("Expected sum at field 1")
                continue
            }
            XCTAssertEqual(tag2, testCase.2)
            
            guard case .sum(let tag3, _) = fields[2] else {
                XCTFail("Expected sum at field 2")
                continue
            }
            XCTAssertEqual(tag3, testCase.4)
        }
    }
    
    func testWriterClearAndReuse() throws {
        let writer = BSATNWriter()
        
        // Write some data
        writer.write(UInt32(123))
        let data1 = writer.finalize()
        XCTAssertEqual(data1.count, 4)
        
        // Write more data (writer should be clear after finalize)
        writer.write(UInt64(456))
        let data2 = writer.finalize()
        XCTAssertEqual(data2.count, 8)
        
        // Explicitly clear and write again
        writer.clear()
        writer.write(UInt8(7))
        let data3 = writer.finalize()
        XCTAssertEqual(data3.count, 1)
        
        // Verify each piece of data independently
        let reader1 = BSATNReader(data: data1)
        XCTAssertEqual(try reader1.read() as UInt32, 123)
        
        let reader2 = BSATNReader(data: data2)
        XCTAssertEqual(try reader2.read() as UInt64, 456)
        
        let reader3 = BSATNReader(data: data3)
        XCTAssertEqual(try reader3.read() as UInt8, 7)
    }
    
    func testBoundaryValues() throws {
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
        
        XCTAssertEqual(try reader.read() as UInt8, UInt8.min)
        XCTAssertEqual(try reader.read() as UInt8, UInt8.max)
        XCTAssertEqual(try reader.read() as UInt16, UInt16.min)
        XCTAssertEqual(try reader.read() as UInt16, UInt16.max)
        XCTAssertEqual(try reader.read() as UInt32, UInt32.min)
        XCTAssertEqual(try reader.read() as UInt32, UInt32.max)
        XCTAssertEqual(try reader.read() as UInt64, UInt64.min)
        XCTAssertEqual(try reader.read() as UInt64, UInt64.max)
        
        XCTAssertEqual(try reader.read() as Int8, Int8.min)
        XCTAssertEqual(try reader.read() as Int8, Int8.max)
        XCTAssertEqual(try reader.read() as Int16, Int16.min)
        XCTAssertEqual(try reader.read() as Int16, Int16.max)
        XCTAssertEqual(try reader.read() as Int32, Int32.min)
        XCTAssertEqual(try reader.read() as Int32, Int32.max)
        XCTAssertEqual(try reader.read() as Int64, Int64.min)
        XCTAssertEqual(try reader.read() as Int64, Int64.max)
    }
}