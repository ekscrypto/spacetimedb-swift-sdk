//import Testing
//import Foundation
//@testable import SpacetimeDB
//
//@Test func codable() throws {
//    let connectionId = ConnectionId()
//    let encoded = try JSONEncoder().encode(connectionId)
//    let decoded = try JSONDecoder().decode(ConnectionId.self, from: encoded)
//    #expect(connectionId == decoded)
//}
//
//@Test func unique() throws {
//    var ids: Set<ConnectionId> = []
//    for _ in 0..<1000 {
//        ids.insert(ConnectionId())
//    }
//    #expect(ids.count == 1000)
//}
//
//@Test func hexRepresentation() throws {
//    let connectionId = ConnectionId()
//    let hexString = connectionId.hexRepresentation
//
//    // Verify it's exactly 32 hex digits
//    #expect(hexString.count == 32)
//
//    // Verify it contains only valid hex characters
//    let validHexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
//    #expect(CharacterSet(charactersIn: hexString).isSubset(of: validHexCharacters))
//
//    // Verify the hex string can be reconstructed to Data equal to rawValue
//    var reconstructedData = Data()
//    for i in stride(from: 0, to: hexString.count, by: 2) {
//        let startIndex = hexString.index(hexString.startIndex, offsetBy: i)
//        let endIndex = hexString.index(startIndex, offsetBy: 2)
//        let byteString = String(hexString[startIndex..<endIndex])
//        guard let byteValue = UInt8(byteString, radix: 16) else {
//            fatalError("Invalid hex byte: \(byteString)")
//        }
//        reconstructedData.append(byteValue)
//    }
//    #expect(reconstructedData == connectionId.rawValue)
//}
