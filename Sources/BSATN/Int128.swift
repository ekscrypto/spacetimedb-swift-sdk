public struct Int128: Equatable, Hashable, CustomStringConvertible {
    public let u0: UInt64
    public let u1: UInt64
    
    public var description: String {
        let hex0 = String(format: "%016llx", u0)
        let hex1 = String(format: "%016llx", u1)
        return hex1 + hex0
    }
}
