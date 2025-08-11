import Foundation

func testIdentityTokenMessage() {
    print("Testing IdentityTokenMessage with UInt128...")
    
    // Test creating a UInt128 for the connection ID
    let connectionId = UInt128(high: 9455561137237407733, low: 13811557130600742291)
    print("Connection ID - High: \(connectionId.high), Low: \(connectionId.low)")
    
    // Test the toString method
    let connectionIdString = connectionId.toString()
    print("Connection ID as string: \(connectionIdString)")
    
    // Test creating an IdentityTokenMessage
    let embeddedIdentity = IdentityTokenMessage.IdentityTokenPayload.EmbeddedIdentity(identity: "test-identity")
    let embeddedConnectionId = IdentityTokenMessage.IdentityTokenPayload.EmbeddedConnectionId(connectionId: connectionId)
    let payload = IdentityTokenMessage.IdentityTokenPayload(
        identity: embeddedIdentity,
        token: "test-token",
        connectionId: embeddedConnectionId
    )
    let message = IdentityTokenMessage(identityToken: payload)
    
    print("IdentityTokenMessage created successfully")
    print("Identity: \(message.identityToken.identity.identity)")
    print("Token: \(message.identityToken.token)")
    print("Connection ID - High: \(message.identityToken.connectionId.connectionId.high)")
    print("Connection ID - Low: \(message.identityToken.connectionId.connectionId.low)")
    
    print("✓ IdentityTokenMessage test completed successfully!")
}