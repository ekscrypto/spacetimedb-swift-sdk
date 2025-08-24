public struct UInt256: Equatable, Hashable, CustomStringConvertible, Sendable {
    public let u0: UInt64
    public let u1: UInt64
    public let u2: UInt64
    public let u3: UInt64
    
    public var description: String {
        let hex0 = String(format: "%016llx", u0)
        let hex1 = String(format: "%016llx", u1)
        let hex2 = String(format: "%016llx", u2)
        let hex3 = String(format: "%016llx", u3)
        return hex3 + hex2 + hex1 + hex0
    }
}
