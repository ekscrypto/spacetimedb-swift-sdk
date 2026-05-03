//
//  TableRowDecoder.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-23.
//


import BSATN

public protocol TableRowDecoder: Sendable {
  var model: ProductModel { get }
  func decode(modelValues: [AlgebraicValue]) throws -> Any

  /// Reader-based fast path used by `BSATNRow`-style decoders. Default
  /// implementation reads an `AlgebraicValue` first and dispatches via
  /// `decode(modelValues:)` — preserving existing behavior for legacy
  /// hand-rolled decoders. New row types can override this directly.
  func decode(reader: BSATNReader) throws -> Any

  /// Optional primary-key extractor used by `client.rowEvents(table:)`
  /// to fold delete+insert pairs into `.updated` events. Default `nil`
  /// (no PK known → only `.inserted`/`.deleted` are emitted).
  var primaryKeyExtractor: (@Sendable (Any) -> AnyHashable?)? { get }
}

public extension TableRowDecoder {
    func decode(reader: BSATNReader) throws -> Any {
        let modelValue = try reader.readAlgebraicValue(as: .product(model))
        guard case .product(let values) = modelValue else {
            throw BSATNError.invalidStructure("Expected product at top level of row")
        }
        return try decode(modelValues: values)
    }

    var primaryKeyExtractor: (@Sendable (Any) -> AnyHashable?)? { nil }
}
