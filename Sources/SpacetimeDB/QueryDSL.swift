//
//  QueryDSL.swift
//  spacetimedb-swift-sdk
//
//  Typed query builder mirroring Rust's `crates/query-builder` + the
//  `SubscriptionBuilder::add_query(|qb| ...)` entry point. Produces a
//  SQL `String` that's then handed to the existing `subscribe([String])`
//  primitive, identical to the Rust SDK's wire behaviour — there is no
//  typed AST sent over the network.
//
//  Public surface (this file):
//      SpacetimeQuery          — protocol with `toSQL() -> String`
//      QueryTable<R>           — `SELECT * FROM "table"`
//      FilteredQuery<R>        — `... WHERE predicate`
//      QueryRow<R>             — virtual row passed into the filter closure
//      QueryColumn<R, V>       — typed column ref; carries comparison ops
//      QueryPredicate<R>       — boolean expression with and/or/negated
//      SQLLiteral              — encoding contract for filter RHS values
//
//  Joins live in QueryDSL+Join.swift. Per-row codegen of typed `Cols`
//  structs (so callers don't need string column names) lives in the
//  spacetime-swift codegen tool.
//

import Foundation
import BSATN

// MARK: Protocol

/// Anything that renders to a SpacetimeDB SQL string. The subscribe
/// machinery accepts `[any SpacetimeQuery]` and forwards to the
/// existing string-based subscription path.
public protocol SpacetimeQuery: Sendable {
    func toSQL() -> String
}

// MARK: Entry — table()

/// `SELECT * FROM "<R.tableName>"`. Use `R.query()` (the convenience
/// extension below) or this initializer directly.
public struct QueryTable<R: BSATNRow>: SpacetimeQuery {
    public let tableName: String

    public init(_ rowType: R.Type = R.self) {
        self.tableName = R.tableName
    }

    public func toSQL() -> String {
        "SELECT * FROM \"\(tableName)\""
    }

    /// Add a `WHERE` clause. The closure receives a virtual row; use
    /// `row.col("id", UInt64.self).eq(42)` (or the typed accessors a
    /// codegen-emitted `Cols` struct provides) to build a predicate.
    public func filter(_ build: (QueryRow<R>) -> QueryPredicate<R>) -> FilteredQuery<R> {
        let row = QueryRow<R>(tableAlias: tableName)
        return FilteredQuery(tableName: tableName, predicate: build(row))
    }
}

/// `... WHERE predicate`. Chainable: a second `filter(...)` AND-combines
/// onto the existing predicate (mirrors Rust's `FromWhere::r#where`).
public struct FilteredQuery<R: BSATNRow>: SpacetimeQuery {
    public let tableName: String
    public let predicate: QueryPredicate<R>

    public func toSQL() -> String {
        "SELECT * FROM \"\(tableName)\" WHERE \(predicate.toSQL())"
    }

    public func filter(_ build: (QueryRow<R>) -> QueryPredicate<R>) -> FilteredQuery<R> {
        let row = QueryRow<R>(tableAlias: tableName)
        return FilteredQuery(tableName: tableName, predicate: predicate.and(build(row)))
    }
}

// MARK: Row + Column

/// Virtual row handed to the filter closure. Use `col(_:_:)` to grab a
/// typed column reference.
public struct QueryRow<R: BSATNRow>: Sendable {
    public let tableAlias: String

    public init(tableAlias: String) {
        self.tableAlias = tableAlias
    }

    public func col<V>(_ name: String, _ type: V.Type = V.self) -> QueryColumn<R, V> {
        QueryColumn(tableAlias: tableAlias, name: name)
    }
}

/// Typed reference to a column. The `V` parameter is the Swift type
/// of the column's values; comparison methods on this struct only
/// accept literals of that type.
public struct QueryColumn<R: BSATNRow, V>: Sendable {
    public let tableAlias: String
    public let name: String

    public init(tableAlias: String, name: String) {
        self.tableAlias = tableAlias
        self.name = name
    }

    /// `"<table>"."<col>"` — quoted SQL ref.
    public var sqlRef: String { "\"\(tableAlias)\".\"\(name)\"" }
}

// MARK: Predicate

/// A SQL boolean expression bound to row type `R` so two predicates
/// from different tables can't accidentally combine.
public struct QueryPredicate<R: BSATNRow>: Sendable {
    public let sql: String

    public init(sql: String) { self.sql = sql }

    public func toSQL() -> String { sql }

    public func and(_ other: QueryPredicate<R>) -> QueryPredicate<R> {
        QueryPredicate(sql: "(\(sql) AND \(other.sql))")
    }

    public func or(_ other: QueryPredicate<R>) -> QueryPredicate<R> {
        QueryPredicate(sql: "(\(sql) OR \(other.sql))")
    }

    public var negated: QueryPredicate<R> {
        QueryPredicate(sql: "NOT (\(sql))")
    }
}

// MARK: Comparison operators

public extension QueryColumn where V: SQLLiteral {
    func eq(_ rhs: V) -> QueryPredicate<R>  { .init(sql: "\(sqlRef) = \(rhs.sqlEncoded)") }
    func ne(_ rhs: V) -> QueryPredicate<R>  { .init(sql: "\(sqlRef) != \(rhs.sqlEncoded)") }
    func gt(_ rhs: V) -> QueryPredicate<R>  { .init(sql: "\(sqlRef) > \(rhs.sqlEncoded)") }
    func lt(_ rhs: V) -> QueryPredicate<R>  { .init(sql: "\(sqlRef) < \(rhs.sqlEncoded)") }
    func gte(_ rhs: V) -> QueryPredicate<R> { .init(sql: "\(sqlRef) >= \(rhs.sqlEncoded)") }
    func lte(_ rhs: V) -> QueryPredicate<R> { .init(sql: "\(sqlRef) <= \(rhs.sqlEncoded)") }
}

public extension QueryColumn where V == Bool {
    /// Truthy bare-column predicate: `"table"."col" = TRUE`. Mirrors
    /// Rust's `Col<T, bool> -> BoolExpr<T>` desugar.
    var isTrue: QueryPredicate<R> { .init(sql: "\(sqlRef) = TRUE") }
    var isFalse: QueryPredicate<R> { .init(sql: "\(sqlRef) = FALSE") }
}

// MARK: SQLLiteral protocol + conformances

/// A value that can appear on the right-hand side of a comparison.
/// Implementations return a SQL literal expression (e.g. `'alice'` for
/// strings, `42` for integers).
public protocol SQLLiteral {
    var sqlEncoded: String { get }
}

extension Bool:    SQLLiteral { public var sqlEncoded: String { self ? "TRUE" : "FALSE" } }
extension Int8:    SQLLiteral { public var sqlEncoded: String { String(self) } }
extension Int16:   SQLLiteral { public var sqlEncoded: String { String(self) } }
extension Int32:   SQLLiteral { public var sqlEncoded: String { String(self) } }
extension Int64:   SQLLiteral { public var sqlEncoded: String { String(self) } }
extension Int:     SQLLiteral { public var sqlEncoded: String { String(self) } }
extension UInt8:   SQLLiteral { public var sqlEncoded: String { String(self) } }
extension UInt16:  SQLLiteral { public var sqlEncoded: String { String(self) } }
extension UInt32:  SQLLiteral { public var sqlEncoded: String { String(self) } }
extension UInt64:  SQLLiteral { public var sqlEncoded: String { String(self) } }
extension UInt:    SQLLiteral { public var sqlEncoded: String { String(self) } }
extension Float:   SQLLiteral { public var sqlEncoded: String { String(self) } }
extension Double:  SQLLiteral { public var sqlEncoded: String { String(self) } }

extension String: SQLLiteral {
    /// Single-quoted with embedded single-quotes doubled — the
    /// SpacetimeDB SQL parser uses standard SQL string literal escaping.
    public var sqlEncoded: String {
        "'" + self.replacingOccurrences(of: "'", with: "''") + "'"
    }
}

// 128/256-bit integers don't conform to LosslessStringConvertible; emit
// as `0x`-prefixed hex (the SpacetimeDB SQL grammar accepts hex
// literals for these widths).
extension UInt128: SQLLiteral { public var sqlEncoded: String { "0x" + description } }
extension UInt256: SQLLiteral { public var sqlEncoded: String { "0x" + description } }
extension Int128:  SQLLiteral { public var sqlEncoded: String { "0x" + description } }
extension Int256:  SQLLiteral { public var sqlEncoded: String { "0x" + description } }

extension Identity: SQLLiteral {
    /// Identities serialize as `0x` + lowercase hex — matches the
    /// SpacetimeDB SQL grammar for `Identity` literals.
    public var sqlEncoded: String { "0x" + hex }
}

extension ConnectionId: SQLLiteral {
    public var sqlEncoded: String { "0x" + hexString }
}

extension Timestamp: SQLLiteral {
    /// Timestamps go on the wire as the µs-since-epoch integer.
    public var sqlEncoded: String { String(microsSinceUnixEpoch) }
}

extension TimeDuration: SQLLiteral {
    public var sqlEncoded: String { String(micros) }
}

// MARK: Optional literal

extension Optional: SQLLiteral where Wrapped: SQLLiteral {
    public var sqlEncoded: String {
        switch self {
        case .none: return "NULL"
        case .some(let v): return v.sqlEncoded
        }
    }
}

// MARK: BSATNRow convenience

public extension BSATNRow {
    /// Shorthand for `QueryTable(Self.self)` — `UserRow.query()`.
    static func query() -> QueryTable<Self> { QueryTable() }
}

// MARK: Typed columns (codegen-emitted accessor)

/// A row type whose codegen has emitted a typed `Cols` struct exposing
/// every SQL-comparable column as a `QueryColumn`. Adopting this
/// protocol unlocks the `$0.cols` accessor inside `filter { ... }`
/// blocks so callers don't need string column names.
///
/// The codegen tool emits this conformance for every table row whose
/// columns map to SQL-encodable Swift types (primitives, String,
/// Identity, ConnectionId, Timestamp, TimeDuration, plus `Optional`
/// of any of those). Columns of unsupported types (arrays, nested
/// structs) are simply omitted from the `Cols` struct.
public protocol BSATNRowQueryable: BSATNRow {
    associatedtype Cols
    static func makeCols(tableAlias: String) -> Cols
}

public extension QueryRow where R: BSATNRowQueryable {
    /// Codegen-emitted typed columns for `R`. Use `$0.cols.<field>`
    /// inside a `filter { ... }` closure instead of `$0.col(_:_:)`.
    var cols: R.Cols { R.makeCols(tableAlias: tableAlias) }
}

// MARK: Subscribe entry point

public extension SpacetimeDBClient {
    /// Typed-query subscribe — each `SpacetimeQuery` renders to a SQL
    /// string and is forwarded to `subscribe([String])`. Mirrors Rust's
    /// `SubscriptionBuilder::add_query(|qb| ...).subscribe()`.
    @discardableResult
    func subscribe(queries: [any SpacetimeQuery]) async throws -> SubscriptionHandle {
        try await subscribe(queries.map { $0.toSQL() })
    }

    /// Variadic shorthand for `subscribe(queries:)`. Lets callers write:
    ///
    ///     try await client.subscribe(UserRow.query(), MessageRow.query())
    ///
    /// instead of building an explicit array.
    @discardableResult
    func subscribe(_ queries: any SpacetimeQuery...) async throws -> SubscriptionHandle {
        try await subscribe(queries: queries)
    }
}
