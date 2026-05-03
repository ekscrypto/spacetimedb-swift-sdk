//
//  QueryDSL+Join.swift
//  spacetimedb-swift-sdk
//
//  Left/right semijoins. Mirrors `crates/query-builder/src/join.rs` in
//  upstream — the SQL output format matches byte-for-byte:
//
//      SELECT "L".* FROM "L" JOIN "R" ON "L"."col" = "R"."col" [WHERE ...]   (left)
//      SELECT "R".* FROM "L" JOIN "R" ON "L"."col" = "R"."col" [WHERE ...]   (right)
//
//  Both shapes use a single equality on a single column pair (the only
//  join shape upstream supports). Swift loosens the type-level
//  guarantee that the join columns are *indexed* — Rust enforces that
//  via `IxCol`/`HasIxCols`/`CanBeLookupTable`, but those require
//  codegen-emitted typed col structs which Swift doesn't yet produce.
//  Server-side validation still rejects joins on non-indexed columns at
//  subscription time, so this only narrows compile-time feedback, not
//  runtime correctness.
//

import Foundation
import BSATN

// MARK: Join condition (column-to-column equality)

/// Equality between two columns of the same Swift type, used as the
/// `ON` condition for a join.
public struct JoinCondition: Sendable {
    public let leftTable: String
    public let leftColumn: String
    public let rightTable: String
    public let rightColumn: String
}

public extension QueryColumn {
    /// Column-to-column equality for use as a JOIN ON condition.
    /// The two columns must share the same Swift type but typically
    /// come from different tables.
    func joinEq<RightR: BSATNRow>(_ other: QueryColumn<RightR, V>) -> JoinCondition {
        JoinCondition(
            leftTable: self.tableAlias, leftColumn: self.name,
            rightTable: other.tableAlias, rightColumn: other.name
        )
    }
}

// MARK: SemiJoin — typed by the side that's returned

/// A semijoin between two tables. The generic parameter `Returned` is
/// the side whose rows the query produces (L for `leftSemijoin`, R for
/// `rightSemijoin`).
public struct SemiJoin<Returned: BSATNRow>: SpacetimeQuery {
    /// Table named in the `FROM` clause (always L, regardless of which
    /// side the SELECT picks).
    public let leftTable: String
    /// Table named in the `JOIN` clause (always R).
    public let rightTable: String
    public let onCondition: JoinCondition
    /// Whether the query returns L rows (true) or R rows (false).
    /// Determines the SELECT clause and which table's WHEREs apply.
    public let returnsLeft: Bool
    /// WHERE applied to the returned side. For left semijoins this is
    /// the only allowed WHERE; for right semijoins it's combined with
    /// `leftSidePredicate` via AND.
    public let predicate: SQLFragment?
    /// Right-semijoin only: an additional WHERE filtering on the L
    /// (non-returned) side. AND-combined with `predicate`.
    public let leftSidePredicate: SQLFragment?

    public init(
        leftTable: String,
        rightTable: String,
        onCondition: JoinCondition,
        returnsLeft: Bool,
        predicate: SQLFragment? = nil,
        leftSidePredicate: SQLFragment? = nil
    ) {
        self.leftTable = leftTable
        self.rightTable = rightTable
        self.onCondition = onCondition
        self.returnsLeft = returnsLeft
        self.predicate = predicate
        self.leftSidePredicate = leftSidePredicate
    }

    public func toSQL() -> String {
        let returningTable = returnsLeft ? leftTable : rightTable
        var sql = "SELECT \"\(returningTable)\".* FROM \"\(leftTable)\" JOIN \"\(rightTable)\" ON " +
                  "\"\(onCondition.leftTable)\".\"\(onCondition.leftColumn)\" = " +
                  "\"\(onCondition.rightTable)\".\"\(onCondition.rightColumn)\""

        // For right semijoins, upstream combines left's then right's
        // WHERE in that order, AND-joined; for left semijoins only the
        // left's WHERE is permitted.
        var parts: [String] = []
        if let lp = leftSidePredicate { parts.append(lp.sql) }
        if let p = predicate { parts.append(p.sql) }
        if !parts.isEmpty {
            sql += " WHERE " + parts.joined(separator: " AND ")
        }
        return sql
    }
}

/// Type-erased SQL fragment — joins carry predicates from either side
/// of the join, so we drop the generic row binding when storing them
/// inside the join struct.
public struct SQLFragment: Sendable {
    public let sql: String
    public init(sql: String) { self.sql = sql }
}

// MARK: QueryTable + FilteredQuery → SemiJoin

public extension QueryTable {
    /// `SELECT "L".* FROM "L" JOIN "R" ON ...` — returns L's rows
    /// filtered to those with a matching R.
    func leftSemijoin<RightR: BSATNRow>(
        _ right: QueryTable<RightR>,
        on: (QueryRow<R>, QueryRow<RightR>) -> JoinCondition
    ) -> SemiJoin<R> {
        let l = QueryRow<R>(tableAlias: tableName)
        let r = QueryRow<RightR>(tableAlias: right.tableName)
        return SemiJoin(
            leftTable: tableName,
            rightTable: right.tableName,
            onCondition: on(l, r),
            returnsLeft: true
        )
    }

    /// `SELECT "R".* FROM "L" JOIN "R" ON ...` — returns R's rows
    /// filtered to those with a matching L.
    func rightSemijoin<RightR: BSATNRow>(
        _ right: QueryTable<RightR>,
        on: (QueryRow<R>, QueryRow<RightR>) -> JoinCondition
    ) -> SemiJoin<RightR> {
        let l = QueryRow<R>(tableAlias: tableName)
        let r = QueryRow<RightR>(tableAlias: right.tableName)
        return SemiJoin(
            leftTable: tableName,
            rightTable: right.tableName,
            onCondition: on(l, r),
            returnsLeft: false
        )
    }
}

public extension FilteredQuery {
    /// Same as `QueryTable.leftSemijoin`, but the existing WHERE is
    /// carried as the L-side predicate. (Right-semijoin only — for
    /// `leftSemijoin` from a `FilteredQuery` the predicate would
    /// filter the join result, which is what the caller probably
    /// wants; see `SemiJoin.filter` instead.)
    func rightSemijoin<RightR: BSATNRow>(
        _ right: QueryTable<RightR>,
        on: (QueryRow<R>, QueryRow<RightR>) -> JoinCondition
    ) -> SemiJoin<RightR> {
        let l = QueryRow<R>(tableAlias: tableName)
        let r = QueryRow<RightR>(tableAlias: right.tableName)
        return SemiJoin(
            leftTable: tableName,
            rightTable: right.tableName,
            onCondition: on(l, r),
            returnsLeft: false,
            predicate: nil,
            leftSidePredicate: SQLFragment(sql: predicate.sql)
        )
    }
}

// MARK: SemiJoin — chainable filter

public extension SemiJoin {
    /// AND-combine an additional predicate on the returned side.
    func filter(_ build: (QueryRow<Returned>) -> QueryPredicate<Returned>) -> SemiJoin<Returned> {
        let returnedTable = returnsLeft ? leftTable : rightTable
        let row = QueryRow<Returned>(tableAlias: returnedTable)
        let next = build(row)
        let combined: SQLFragment
        if let existing = predicate {
            combined = SQLFragment(sql: "(\(existing.sql) AND \(next.sql))")
        } else {
            combined = SQLFragment(sql: next.sql)
        }
        return SemiJoin(
            leftTable: leftTable,
            rightTable: rightTable,
            onCondition: onCondition,
            returnsLeft: returnsLeft,
            predicate: combined,
            leftSidePredicate: leftSidePredicate
        )
    }
}
