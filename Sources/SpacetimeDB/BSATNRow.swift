//
//  BSATNRow.swift
//  spacetimedb-swift-sdk
//
//  Phase 5: protocol-based boilerplate killer for table rows.
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

public extension BSATNRow {
    /// One-line registration helper:
    /// `client.registerTableRowDecoder(MyRow.self)`.
    static func decoder() -> TableRowDecoder { GenericTableRowDecoder<Self>() }
}

public extension SpacetimeDBClient {
    /// Register a `BSATNRow` type — uses its `tableName` and the generic
    /// reader-based decoder. No need to hand-roll a `TableRowDecoder`.
    func registerTableRowDecoder<R: BSATNRow>(_ type: R.Type) {
        registerTableRowDecoder(table: R.tableName, decoder: R.decoder())
    }
}

/// Adapter that lets any `BSATNRow` plug into the existing
/// `TableRowDecoder` interface. Skips the AlgebraicValue intermediate;
/// the receive loop calls `decode(reader:)` directly.
public struct GenericTableRowDecoder<R: BSATNRow>: TableRowDecoder {
    public init() {}

    /// `model` is only consulted by the legacy (modelValues-based) path
    /// in `TableRowDecoder`'s default extension. `BSATNRow` types skip
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
