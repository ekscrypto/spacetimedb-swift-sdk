//
//  BSATNRow.swift
//  spacetimedb-swift-sdk
//
//  Protocol-based boilerplate killer for table rows.
//
//  A `BSATNRow` is a value type that knows how to decode itself
//  from a `BSATNReader` field-by-field, in declared order. The SDK
//  ships a generic `TableRowDecoder` that adapts any `BSATNRow` to
//  the existing decoder protocol — no per-row `Model: ProductModel`,
//  no `init(modelValues:)`, no per-table `Decoder` boilerplate.
//

import Foundation
import BSATN

/// Adopt on a struct that mirrors a SpacetimeDB table row. The single
/// requirement is `init(reader:)` — read each field in declared order.
public protocol BSATNRow {
    init(reader: BSATNReader) throws
    static var tableName: String { get }
}

/// Row whose table has a primary key. Conforming types unlock
/// `.updated(old:new:)` events on the per-row stream — the SDK matches
/// delete+insert pairs by PK within a single transaction.
///
/// Mirrors Rust's `TableWithPrimaryKey` distinction.
public protocol BSATNTableWithPrimaryKey: BSATNRow {
    associatedtype PrimaryKey: Hashable & Sendable
    var primaryKey: PrimaryKey { get }
}

public extension BSATNRow {
    /// One-line registration helper:
    /// `client.registerTableRowDecoder(MyRow.self)`.
    static func decoder() -> TableRowDecoder { GenericTableRowDecoder<Self>(primaryKeyExtractor: nil) }
}

public extension BSATNTableWithPrimaryKey {
    /// Override that supplies the PK extractor so per-row update
    /// detection works. Picked over the `BSATNRow` default by Swift's
    /// most-constrained overload resolution.
    static func decoder() -> TableRowDecoder {
        let extractor: @Sendable (Any) -> AnyHashable? = { value in
            (value as? Self).map { AnyHashable($0.primaryKey) }
        }
        return GenericTableRowDecoder<Self>(primaryKeyExtractor: extractor)
    }
}

public extension SpacetimeDBClient {
    /// Register a `BSATNRow` type — uses its `tableName` and the generic
    /// reader-based decoder. No need to hand-roll a `TableRowDecoder`.
    func registerTableRowDecoder<R: BSATNRow>(_ type: R.Type) {
        registerTableRowDecoder(table: R.tableName, decoder: R.decoder())
    }

    /// Specialized overload for tables with a primary key — chosen when
    /// the registered row type conforms to `BSATNTableWithPrimaryKey`.
    /// Without this overload Swift would pick the `BSATNRow` version
    /// above (which produces a decoder without a PK extractor) because
    /// protocol witness dispatch ignores conditional extensions on
    /// generic types.
    func registerTableRowDecoder<R: BSATNTableWithPrimaryKey>(_ type: R.Type) {
        registerTableRowDecoder(table: R.tableName, decoder: R.decoder())
    }
}

/// Adapter that lets any `BSATNRow` plug into the existing
/// `TableRowDecoder` interface. Skips the AlgebraicValue intermediate;
/// the receive loop calls `decode(reader:)` directly.
public struct GenericTableRowDecoder<R: BSATNRow>: TableRowDecoder {
    public let primaryKeyExtractor: (@Sendable (Any) -> AnyHashable?)?

    public init(primaryKeyExtractor: (@Sendable (Any) -> AnyHashable?)? = nil) {
        self.primaryKeyExtractor = primaryKeyExtractor
    }

    /// `model` is only consulted by the modelValues-based path in
    /// `TableRowDecoder`'s default extension. `BSATNRow` types skip
    /// that path entirely; this stub is never read in practice.
    public var model: ProductModel { _UnusedProductModel() }

    public func decode(modelValues: [AlgebraicValue]) throws -> Any {
        throw BSATNError.notImplemented
    }

    public func decode(reader: BSATNReader) throws -> Any {
        try R(reader: reader)
    }
}

private struct _UnusedProductModel: ProductModel {
    var definition: [AlgebraicValueType] { [] }
}
