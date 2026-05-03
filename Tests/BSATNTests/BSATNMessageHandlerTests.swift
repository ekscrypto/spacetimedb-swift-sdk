import Testing
import Foundation
@testable import BSATN

@Suite("BSATNMessageHandler Tests")
struct BSATNMessageHandlerTests {

    struct TestProductModel: ProductModel {
        let definition: [AlgebraicValueType]

        init(_ definition: [AlgebraicValueType]) {
            self.definition = definition
        }
    }

    struct TestArrayModel: ArrayModel {
        let definition: AlgebraicValueType

        init(of type: AlgebraicValueType) {
            self.definition = type
        }
    }

    @Test("Process uncompressed message with known tag")
    func processUncompressedMessage() throws {
        // Set up handler with supported tags
        let supportedTags: [UInt8: ProductModel] = [
            5: TestProductModel([.uint32, .string])
        ]
        let handler = BSATNMessageHandler(supportedTags: supportedTags)

        // Create test message
        let writer = BSATNWriter()
        writer.write(UInt8(0)) // Compression: uncompressed
        writer.write(UInt8(5)) // Tag: 5
        writer.write(UInt32(42))
        try writer.write("test message")

        let data = writer.finalize()

        // Process message
        let decoded = try handler.processMessage(data)

        #expect(decoded.tag == 5)
        #expect(decoded.values.count == 2)

        guard case .uint32(let value1) = decoded.values[0] else {
            Issue.record("Expected uint32")
            return
        }
        #expect(value1 == 42)

        guard case .string(let value2) = decoded.values[1] else {
            Issue.record("Expected string")
            return
        }
        #expect(value2 == "test message")
    }

    @Test("Process message with unsupported tag")
    func processUnsupportedTag() throws {
        let supportedTags: [UInt8: ProductModel] = [
            5: TestProductModel([.uint32])
        ]
        let handler = BSATNMessageHandler(supportedTags: supportedTags)

        let writer = BSATNWriter()
        writer.write(UInt8(0)) // Compression: uncompressed
        writer.write(UInt8(99)) // Tag: 99 (unsupported)
        writer.write(UInt32(42))

        let data = writer.finalize()

        #expect {
            try handler.processMessage(data)
        } throws: { error in
            guard case BSATNError.unsupportedTag(let tag) = error else { return false }
            return tag == 99
        }
    }

    @Test("Process message with compressed data throws not implemented")
    func processCompressedMessage() throws {
        let supportedTags: [UInt8: ProductModel] = [
            5: TestProductModel([.uint32])
        ]
        let handler = BSATNMessageHandler(supportedTags: supportedTags)

        let writer = BSATNWriter()
        writer.write(UInt8(1)) // Compression: gzip (not supported)
        writer.write(UInt8(5)) // Tag: 5
        writer.write(UInt32(42))

        let data = writer.finalize()

        #expect {
            try handler.processMessage(data)
        } throws: { error in
            guard case BSATNError.notImplemented = error else { return false }
            return true
        }
    }

    @Test("Process message with complex product")
    func processComplexProduct() throws {
        let supportedTags: [UInt8: ProductModel] = [
            10: TestProductModel([.uint256, .bool, .array(TestArrayModel(of: .uint8))])
        ]
        let handler = BSATNMessageHandler(supportedTags: supportedTags)

        let writer = BSATNWriter()
        writer.write(UInt8(0)) // Compression: uncompressed
        writer.write(UInt8(10)) // Tag: 10

        // Write UInt256
        let uint256 = UInt256(u0: 1, u1: 2, u2: 3, u3: 4)
        writer.write(uint256)

        // Write bool
        writer.write(true)

        // Write array of uint8
        try writer.writeAlgebraicValue(.array([.uint8(10), .uint8(20), .uint8(30)]))

        let data = writer.finalize()

        let decoded = try handler.processMessage(data)

        #expect(decoded.tag == 10)
        #expect(decoded.values.count == 3)

        guard case .uint256(let decodedUInt256) = decoded.values[0] else {
            Issue.record("Expected uint256")
            return
        }
        #expect(decodedUInt256 == uint256)

        guard case .bool(let decodedBool) = decoded.values[1] else {
            Issue.record("Expected bool")
            return
        }
        #expect(decodedBool == true)

        guard case .array(let decodedArray) = decoded.values[2] else {
            Issue.record("Expected array")
            return
        }
        #expect(decodedArray.count == 3)
    }

    @Test("DecodedMessage properties")
    func decodedMessageProperties() {
        let tag: UInt8 = 42
        let values: [AlgebraicValue] = [.uint32(100), .string("test")]

        let message = DecodedMessage(tag: tag, values: values)

        #expect(message.tag == 42)
        #expect(message.values.count == 2)

        guard case .uint32(let value1) = message.values[0] else {
            Issue.record("Expected uint32")
            return
        }
        #expect(value1 == 100)

        guard case .string(let value2) = message.values[1] else {
            Issue.record("Expected string")
            return
        }
        #expect(value2 == "test")
    }
}