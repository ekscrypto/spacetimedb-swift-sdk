import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("Typed Procedure")
struct ProcedureTests {

    // MARK: A small typed procedure used across tests.

    /// Looks up a user by `UInt64` id, returning a `(name, online)` pair.
    /// The decoder reads `string` then `bool` from the payload.
    struct LookupUserProc: Procedure {
        typealias ReturnValue = (name: String, online: Bool)

        let name = "lookup_user"
        let userId: UInt64

        func encodeArguments(writer: BSATNWriter) throws {
            writer.write(userId)
        }

        func decodeReturnValue(_ data: Data) throws -> (name: String, online: Bool) {
            let r = BSATNReader(data: data)
            let nm = try r.readString()
            let on: Bool = try r.read()
            return (nm, on)
        }
    }

    @Test func encodesArgsViaTypedProcedure() throws {
        let writer = BSATNWriter()
        try LookupUserProc(userId: 0x1122_3344_5566_7788).encodeArguments(writer: writer)
        let bytes = Array(writer.finalize())
        // u64 little-endian
        #expect(bytes == [0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11])
    }

    @Test func decodesTypedReturnValue() throws {
        // Build a "name=Alice, online=true" payload.
        let w = BSATNWriter()
        try w.write("Alice")
        w.write(true)
        let payload = w.finalize()

        let result = try LookupUserProc(userId: 1).decodeReturnValue(payload)
        #expect(result.name == "Alice")
        #expect(result.online == true)
    }

    @Test func voidProcedureProducesEmptyArgs() throws {
        let writer = BSATNWriter()
        try VoidProcedure(name: "noop").encodeArguments(writer: writer)
        #expect(writer.finalize().isEmpty)
    }

    @Test func rawProcedurePassesArgsThrough() throws {
        let writer = BSATNWriter()
        try RawProcedure(name: "raw", encodedArguments: Data([0xAA, 0xBB, 0xCC])).encodeArguments(writer: writer)
        #expect(Array(writer.finalize()) == [0xAA, 0xBB, 0xCC])
    }

    @Test func defaultDecoderReturnsRawDataWhenReturnTypeIsData() throws {
        let proc = RawProcedure(name: "r")
        let payload = Data([1, 2, 3])
        let returned = try proc.decodeReturnValue(payload)
        #expect(returned == payload)
    }

    @Test func endToEndCallProcedureRequestRoundTrip() throws {
        // Verify that the typed-procedure path produces the same wire
        // bytes as the raw path: encode args via the protocol, build a
        // CallProcedureRequest with those bytes, decode, compare.
        let proc = LookupUserProc(userId: 42)
        let writer = BSATNWriter()
        try proc.encodeArguments(writer: writer)
        let typedArgs = writer.finalize()

        let req = CallProcedureRequest(
            procedure: proc.name,
            arguments: typedArgs,
            requestId: 7,
            flags: .default
        )
        let encoded = try req.encode()

        // Verify field by field.
        let r = BSATNReader(data: encoded)
        let tag: UInt8 = try r.read()
        #expect(tag == Tags.ClientMessage.callProcedure.rawValue)
        let reqId: UInt32 = try r.read()
        #expect(reqId == 7)
        let _: UInt8 = try r.read()    // flags
        let nameLen: UInt32 = try r.read()
        var nameBytes: [UInt8] = []
        for _ in 0..<nameLen { nameBytes.append(try r.read()) }
        #expect(String(bytes: nameBytes, encoding: .utf8) == "lookup_user")
        let argsLen: UInt32 = try r.read()
        #expect(argsLen == 8)
    }
}
