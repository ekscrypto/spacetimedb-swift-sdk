//
//  Range.swift
//  spacetimedb-swift-sdk
//
//  Phase 15: SpacetimeDB Bound + Range value types. Mirrors the TS v3
//  SDK's `range.ts` shape (`Bound<T>` + `Range<T>`) used by typed
//  index filters: `db.user.byEmail.filter(Range.starting("a"))`.
//
//  These are pure client-side helpers — they don't go on the wire as
//  BSATN values. They're consumed by codegen-emitted index accessors
//  to render a SQL `WHERE` clause covering the bound's interval.
//

import Foundation

/// Half-bound of a range. `inclusive(value)` means the bound IS in
/// the range; `exclusive(value)` means it is NOT; `unbounded` means
/// the range extends arbitrarily far in that direction.
public enum Bound<T: Sendable & Comparable>: Sendable {
    case inclusive(T)
    case exclusive(T)
    case unbounded

    public var isUnbounded: Bool {
        if case .unbounded = self { return true }
        return false
    }

    public var value: T? {
        switch self {
        case .inclusive(let v), .exclusive(let v): return v
        case .unbounded: return nil
        }
    }

    public var isInclusive: Bool {
        if case .inclusive = self { return true }
        return false
    }
}

extension Bound: Equatable where T: Equatable {}
extension Bound: Hashable where T: Hashable {}

/// A continuous interval `[low, high]` whose endpoints are each a
/// `Bound<T>`. Used as the input to typed index filter accessors.
///
/// Convenience constructors mirror Rust's `Range::new` plus the
/// half-open / inclusive / exclusive shorthands.
public struct Range<T: Sendable & Comparable>: Sendable {
    public let lower: Bound<T>
    public let upper: Bound<T>

    public init(lower: Bound<T>, upper: Bound<T>) {
        self.lower = lower
        self.upper = upper
    }

    /// `value..value` — all rows whose key equals `value`.
    public static func equal(_ value: T) -> Range<T> {
        Range(lower: .inclusive(value), upper: .inclusive(value))
    }

    /// `[value, ∞)` — all rows whose key is ≥ value.
    public static func startingAt(_ value: T) -> Range<T> {
        Range(lower: .inclusive(value), upper: .unbounded)
    }

    /// `(value, ∞)` — all rows whose key is > value.
    public static func startingAfter(_ value: T) -> Range<T> {
        Range(lower: .exclusive(value), upper: .unbounded)
    }

    /// `(-∞, value]` — all rows whose key is ≤ value.
    public static func endingAt(_ value: T) -> Range<T> {
        Range(lower: .unbounded, upper: .inclusive(value))
    }

    /// `(-∞, value)` — all rows whose key is < value.
    public static func endingBefore(_ value: T) -> Range<T> {
        Range(lower: .unbounded, upper: .exclusive(value))
    }

    /// `[low, high]` (both endpoints inclusive).
    public static func closed(from low: T, to high: T) -> Range<T> {
        Range(lower: .inclusive(low), upper: .inclusive(high))
    }

    /// `[low, high)` — Swift's `..<` semantics.
    public static func halfOpen(from low: T, to high: T) -> Range<T> {
        Range(lower: .inclusive(low), upper: .exclusive(high))
    }

    /// `(-∞, ∞)` — every row passes.
    public static var unbounded: Range<T> {
        Range(lower: .unbounded, upper: .unbounded)
    }

    /// Test whether `value` falls inside the range. Useful for
    /// client-side filtering of cached rows; the server-side index
    /// accessor produces the same predicate by other means.
    public func contains(_ value: T) -> Bool {
        let inLower: Bool = {
            switch lower {
            case .unbounded:        return true
            case .inclusive(let l): return value >= l
            case .exclusive(let l): return value > l
            }
        }()
        let inUpper: Bool = {
            switch upper {
            case .unbounded:        return true
            case .inclusive(let u): return value <= u
            case .exclusive(let u): return value < u
            }
        }()
        return inLower && inUpper
    }
}

extension Range: Equatable where T: Equatable {}
extension Range: Hashable where T: Hashable {}
