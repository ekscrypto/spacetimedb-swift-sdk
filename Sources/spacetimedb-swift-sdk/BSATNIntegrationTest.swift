import Foundation
import BSATN

func testBSATNIntegration() {
    print("Testing BSATN Integration...")
    
    // Test creating and using UInt128 from BSATN
    let testValue = UInt128(high: 0x1234567890ABCDEF, low: 0xFEDCBA0987654321)
    print("Created UInt128 - High: \(testValue.high), Low: \(testValue.low)")
    
    // Test BSATN encoding
    let bsatnData = testValue.toBSATN()
    print("Encoded to BSATN: \(bsatnData.count) bytes")
    
    // Test BSATN decoding
    do {
        let decodedValue = try UInt128.fromBSATN(bsatnData)
        print("Decoded UInt128 - High: \(decodedValue.high), Low: \(decodedValue.low)")
        print("Values match: \(testValue == decodedValue ? "YES" : "NO")")
    } catch {
        print("Error decoding: \(error)")
    }
    
    // Test BSATN reader/writer
    let writer = BSATNWriter()
    writer.writeUInt128(testValue)
    writer.writeBool(true)
    writer.writeUInt32(42)
    
    let reader = BSATNReader(data: writer.writtenData)
    do {
        let readUint128 = try reader.readUInt128()
        let readBool = try reader.readBool()
        let readUint32 = try reader.readUInt32()
        
        print("Reader/Writer test:")
        print("  UInt128 - High: \(readUint128.high), Low: \(readUint128.low)")
        print("  Bool: \(readBool)")
        print("  UInt32: \(readUint32)")
    } catch {
        print("Error in reader/writer test: \(error)")
    }
    
    print("BSATN Integration test completed!")
}