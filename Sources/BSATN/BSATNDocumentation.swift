/*
 BSATN (Binary SATN) Implementation for Swift

 This implementation provides utilities for working with SpacetimeDB's
 Binary SATN Format as documented at:
 https://github.com/clockworklabs/SpacetimeDB/blob/master/docs/docs/bsatn.md

 Key Features:

 1. UInt128 Support:
    - UInt128 struct with BSATN encoding/decoding
    - Converts between Swift UInt128 and 16-byte little-endian format
    - Error handling for invalid data sizes

 2. BSATN Reader:
    - Utility class for reading BSATN-encoded binary data streams
    - Supports all primitive types defined in BSATN spec
    - Little-endian byte order for multi-byte values

 3. BSATN Writer:
    - Utility class for writing BSATN-encoded binary data streams
    - Supports all primitive types defined in BSATN spec
    - Little-endian byte order for multi-byte values

 4. AlgebraicValue:
    - Complete enum representing all BSATN types
    - Supports recursive types (arrays, products, sums)

 5. Binary Format Details:
    - UInt8: 1 byte
    - UInt16: 2 bytes (little-endian)
    - UInt32: 4 bytes (little-endian)
    - UInt64: 8 bytes (little-endian)
    - UInt128: 16 bytes (little-endian)
    - String: UInt32 length prefix + UTF-8 bytes
    - Arrays: UInt32 count + elements
    - Products: Concatenated field values
    - Sums: UInt8 tag + variant data

 Usage Examples:

 // Reading a UInt128 from BSATN data
 let reader = BSATNReader(data: binaryData)
 let uint128Value = try reader.readUInt128()

 // Converting UInt128 to/from BSATN manually
 let bsatnData = uint128Value.toBSATN()
 let decodedValue = try UInt128.fromBSATN(bsatnData)

 // Working with AlgebraicValues
 let value: AlgebraicValue = .uint128(UInt128(high: 123, low: 456))
 let writer = BSATNWriter()
 try writer.writeAlgebraicValue(value)

 Notes:
 - All multi-byte values use little-endian byte order
 - Strings are UTF-8 encoded with UInt32 length prefix
 - Large integers (128-bit+) must be handled as binary data, not JSON
 - JSON cannot reliably represent 128-bit integers due to precision limits
 */