import Foundation

/// Represents an AlgebraicValue as defined in the BSATN spec
public indirect enum AlgebraicValue: Equatable {
    case bool(Bool)
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case uint64(UInt64)
    case uint128(UInt128)
    case int8(Int8)
    case int16(Int16)
    case int32(Int32)
    case int64(Int64)
    case int128(Int128) // You might want to implement Int128 similar to UInt128
    case float32(Float)
    case float64(Double)
    case string(String)
    case array([AlgebraicValue])
    case product([AlgebraicValue])
    case sum(tag: UInt8, value: AlgebraicValue?)
}

// Simple Int128 implementation for completeness
public struct Int128: Equatable, Hashable {
    public let high: Int64
    public let low: UInt64
    
    public init(high: Int64, low: UInt64) {
        self.high = high
        self.low = low
    }
}