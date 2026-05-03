import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("BSATNRow protocol Tests")
struct BSATNRowTests {

    struct PrimitiveRow: BSATNRow, Equatable {
        static let tableName = "primitive"
        let a: UInt32
        let b: Bool
        let c: String

        init(a: UInt32, b: Bool, c: String) {
            self.a = a; self.b = b; self.c = c
        }

        init(reader: BSATNReader) throws {
            self.a = try reader.read()
            self.b = try reader.read()
            self.c = try reader.readString()
        }
    }

    struct OptionalRow: BSATNRow, Equatable {
        static let tableName = "optional"
        let id: UInt256
        let name: String?
        let online: Bool

        init(id: UInt256, name: String?, online: Bool) {
            self.id = id; self.name = name; self.online = online
        }

        init(reader: BSATNReader) throws {
            self.id = try reader.read()
            self.name = try reader.readOptional { try reader.readString() }
            self.online = try reader.read()
        }
    }

    @Test func primitiveRowDecodesViaGenericDecoder() throws {
        let writer = BSATNWriter()
        writer.write(UInt32(42))
        writer.write(true)
        try writer.write("hello")
        let reader = BSATNReader(data: writer.finalize())

        let decoder = PrimitiveRow.decoder()
        let any = try decoder.decode(reader: reader)
        let row = try #require(any as? PrimitiveRow)
        #expect(row == PrimitiveRow(a: 42, b: true, c: "hello"))
    }

    @Test func optionalRowSomeAndNone() throws {
        let id = UInt256(u0: 1, u1: 2, u2: 3, u3: 4)

        // Some("alice")
        let w1 = BSATNWriter()
        w1.write(id)
        w1.write(UInt8(0))                // Option tag: 0 = Some
        try w1.write("alice")
        w1.write(true)
        let some = try OptionalRow(reader: BSATNReader(data: w1.finalize()))
        #expect(some == OptionalRow(id: id, name: "alice", online: true))

        // None
        let w2 = BSATNWriter()
        w2.write(id)
        w2.write(UInt8(1))                // Option tag: 1 = None
        w2.write(false)
        let none = try OptionalRow(reader: BSATNReader(data: w2.finalize()))
        #expect(none == OptionalRow(id: id, name: nil, online: false))
    }

    @Test func tableRowDecoderViaDefaultDecodeReaderExtension() throws {
        // A hand-rolled decoder that only implements `decode(modelValues:)`
        // should still receive the reader path via the default extension
        // on `TableRowDecoder`.
        struct HandRolledModel: ProductModel {
            var definition: [AlgebraicValueType] { [.uint32, .bool] }
        }
        struct HandRolledDecoder: TableRowDecoder {
            var model: ProductModel { HandRolledModel() }
            func decode(modelValues: [AlgebraicValue]) throws -> Any {
                guard case .uint32(let a) = modelValues[0],
                      case .bool(let b) = modelValues[1] else {
                    throw BSATNError.invalidStructure("HandRolled")
                }
                return [a, b] as [Any]
            }
        }

        let writer = BSATNWriter()
        writer.write(UInt32(7))
        writer.write(false)
        let reader = BSATNReader(data: writer.finalize())

        let any = try HandRolledDecoder().decode(reader: reader)
        let arr = try #require(any as? [Any])
        #expect((arr[0] as? UInt32) == 7)
        #expect((arr[1] as? Bool) == false)
    }

    @Test func registerTableRowDecoderHelper() async throws {
        let client = try SpacetimeDBClient(host: "http://localhost:3000", db: "test")
        await client.registerTableRowDecoder(PrimitiveRow.self)
        let decoder = await client.decoder(forTable: "primitive")
        #expect(decoder is GenericTableRowDecoder<PrimitiveRow>)
    }
}
