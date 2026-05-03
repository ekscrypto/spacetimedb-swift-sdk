import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("IdentityTokenMessage Tests")
struct IdentityTokenMessageTests {

    @Test("Create IdentityTokenMessage from model values")
    func createIdentityTokenMessage() throws {
        let identity = UInt256(u0: 0x1234567890ABCDEF, u1: 0xFEDCBA0987654321,
                               u2: 0x1111111111111111, u3: 0x2222222222222222)
        let token = "test-auth-token-12345"
        let connectionId = UInt128(u0: 0x1234, u1: 0x5678)

        let modelValues: [AlgebraicValue] = [
            .uint256(identity),
            .string(token),
            .uint128(connectionId)
        ]

        let message = try IdentityTokenMessage(modelValues: modelValues)

        #expect(message.identity == identity)
        #expect(message.token == token)
        #expect(message.connectionId == connectionId)
    }

    @Test("IdentityTokenMessage with empty token")
    func identityTokenMessageEmptyToken() throws {
        let identity = UInt256(u0: 1, u1: 2, u2: 3, u3: 4)
        let connectionId = UInt128(u0: 0, u1: 0)

        let modelValues: [AlgebraicValue] = [
            .uint256(identity),
            .string(""),
            .uint128(connectionId)
        ]

        let message = try IdentityTokenMessage(modelValues: modelValues)

        #expect(message.identity == identity)
        #expect(message.token == "")
        #expect(message.connectionId == connectionId)
    }

    @Test("IdentityTokenMessage with AlgebraicValue")
    func identityTokenMessageAlgebraicValue() throws {
        let identity = UInt256(u0: 0xDEADBEEF, u1: 0xCAFEBABE, u2: 0, u3: 0)
        let token = "algebraic-token"
        let connectionId = UInt128(u0: 0xAAAA, u1: 0xBBBB)

        let writer = BSATNWriter()
        try writer.writeAlgebraicValue(.product([
            .uint256(identity),
            .string(token),
            .uint128(connectionId)
        ]))

        let data = writer.finalize()
        let reader = BSATNReader(data: data)

        let modelValues = try reader.readAlgebraicValue(as: .product(IdentityTokenMessage.Model()))
        guard case .product(let values) = modelValues else {
            Issue.record("Expected product")
            return
        }

        let message = try IdentityTokenMessage(modelValues: values)

        #expect(message.identity == identity)
        #expect(message.token == token)
        #expect(message.connectionId == connectionId)
    }
}