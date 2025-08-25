#!/usr/bin/env swift

import Foundation
import BSATN
import SpacetimeDB
import quickstart_chat

// Test data: A user row with identity, name="TestUser", online=true
// This simulates what we'd receive from the server

// Create test data
let testData = Data([
    // Identity (32 bytes of 0x42)
    0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
    0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
    0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
    0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42,
    // Optional name: tag 0 (Some)
    0x00,
    // String length (8 bytes for "TestUser")
    0x08, 0x00, 0x00, 0x00,
    // String data "TestUser"
    0x54, 0x65, 0x73, 0x74, 0x55, 0x73, 0x65, 0x72,
    // Bool online: true
    0x01
])

do {
    let reader = BSATNReader(data: testData, debugEnabled: true)
    let user = try UserRow(reader: reader)
    
    print("\n=== Direct Reader Test ===")
    print("Identity: \(user.identity.description.prefix(16))...")
    print("Name: \(user.name ?? "nil")")
    print("Online: \(user.online)")
    
    // Now test through the modelValues path
    print("\n=== ModelValues Path Test ===")
    let reader2 = BSATNReader(data: testData, debugEnabled: false)
    let model = UserRow.Model()
    let productValue = try reader2.readAlgebraicValue(as: .product(model))
    
    guard case .product(let values) = productValue else {
        print("ERROR: Expected product value")
        exit(1)
    }
    
    let user2 = try UserRow(modelValues: values)
    print("Identity: \(user2.identity.description.prefix(16))...")
    print("Name: \(user2.name ?? "nil")")
    print("Online: \(user2.online)")
    
    // Test None case
    print("\n=== Test None Case ===")
    let testDataNone = Data([
        // Identity (32 bytes of 0x43)
        0x43, 0x43, 0x43, 0x43, 0x43, 0x43, 0x43, 0x43,
        0x43, 0x43, 0x43, 0x43, 0x43, 0x43, 0x43, 0x43,
        0x43, 0x43, 0x43, 0x43, 0x43, 0x43, 0x43, 0x43,
        0x43, 0x43, 0x43, 0x43, 0x43, 0x43, 0x43, 0x43,
        // Optional name: tag 1 (None)
        0x01,
        // Bool online: false
        0x00
    ])
    
    let reader3 = BSATNReader(data: testDataNone, debugEnabled: false)
    let user3 = try UserRow(reader: reader3)
    print("Identity: \(user3.identity.description.prefix(16))...")
    print("Name: \(user3.name ?? "nil")")
    print("Online: \(user3.online)")
    
    print("\n✅ All tests passed!")
    
} catch {
    print("❌ Error: \(error)")
    exit(1)
}