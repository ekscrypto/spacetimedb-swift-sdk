import Foundation

/// Helper struct for representing Option types as Sum types
/// Tag 0 = Some (has value), Tag 1 = None (no value)
public struct OptionModel: SumModel {
    public static var size: UInt32 { 2 }
    public let wrappedType: AlgebraicValueType
    
    public init(_ wrappedType: AlgebraicValueType) {
        self.wrappedType = wrappedType
    }
}