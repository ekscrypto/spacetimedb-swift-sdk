import Foundation

public protocol Packed {
    func appended(to data: inout Data)
}

extension Bool: Packed {
    public func appended(to data: inout Data) {
        let value: UInt8 = self ? 1 : 0
        value.appended(to: &data)
    }
}
extension UInt8: Packed {}
extension UInt16: Packed {}
extension UInt32: Packed {}
extension UInt64: Packed {}
extension UInt128: Packed {}
extension UInt256: Packed {}
extension Int8: Packed {}
extension Int16: Packed {}
extension Int32: Packed {}
extension Int64: Packed {}
extension Int128: Packed {}
extension Int256: Packed {}
extension Float32: Packed {}
extension Float64: Packed {}

extension ArraySlice where Element == UInt8 {
    func unpacked() throws -> Bool {
        let value: UInt8 = try unpacked()
        return value != 0
    }

    func unpacked<T: Packed>() throws -> T {
        guard let value = self.withUnsafeBytes({ $0.assumingMemoryBound(to: T.self).first }) else {
            throw BSATNError.insufficientData
        }
        return value
    }
}

extension Packed {
    public func appended(to data: inout Data) {
        var mutable = self
        withUnsafeBytes(of: &mutable) { bufferPointer in
            let bytes = bufferPointer.assumingMemoryBound(to: UInt8.self)
            data.append(bytes)
        }
    }
}

