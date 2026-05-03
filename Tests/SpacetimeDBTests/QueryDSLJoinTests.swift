import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("Typed Query DSL — Joins")
struct QueryDSLJoinTests {

    struct PlayerLevelRow: BSATNRow {
        static let tableName = "player_level"
        let entityId: UInt64
        let level: UInt32
        init(reader: BSATNReader) throws {
            self.entityId = try reader.read()
            self.level = try reader.read()
        }
    }

    struct PlayerRow: BSATNRow {
        static let tableName = "player"
        let entityId: UInt64
        let name: String
        init(reader: BSATNReader) throws {
            self.entityId = try reader.read()
            self.name = try reader.readString()
        }
    }

    @Test func leftSemijoinBareSQL() {
        let q = PlayerLevelRow.query()
            .leftSemijoin(PlayerRow.query()) { lvl, pl in
                lvl.col("entity_id", UInt64.self).joinEq(pl.col("entity_id", UInt64.self))
            }
        #expect(q.toSQL() ==
            "SELECT \"player_level\".* FROM \"player_level\" JOIN \"player\" ON " +
            "\"player_level\".\"entity_id\" = \"player\".\"entity_id\""
        )
    }

    @Test func rightSemijoinPicksRightSideForSelect() {
        let q = PlayerLevelRow.query()
            .rightSemijoin(PlayerRow.query()) { lvl, pl in
                lvl.col("entity_id", UInt64.self).joinEq(pl.col("entity_id", UInt64.self))
            }
        #expect(q.toSQL() ==
            "SELECT \"player\".* FROM \"player_level\" JOIN \"player\" ON " +
            "\"player_level\".\"entity_id\" = \"player\".\"entity_id\""
        )
    }

    @Test func leftSemijoinFilterAppliesToReturnedSide() {
        // Filter is on player_level (the returned side).
        let q = PlayerLevelRow.query()
            .leftSemijoin(PlayerRow.query()) { lvl, pl in
                lvl.col("entity_id", UInt64.self).joinEq(pl.col("entity_id", UInt64.self))
            }
            .filter { $0.col("level", UInt32.self).eq(0) }
        #expect(q.toSQL() ==
            "SELECT \"player_level\".* FROM \"player_level\" JOIN \"player\" ON " +
            "\"player_level\".\"entity_id\" = \"player\".\"entity_id\"" +
            " WHERE \"player_level\".\"level\" = 0"
        )
    }

    @Test func rightSemijoinFilterAppliesToRightSide() {
        let q = PlayerLevelRow.query()
            .rightSemijoin(PlayerRow.query()) { lvl, pl in
                lvl.col("entity_id", UInt64.self).joinEq(pl.col("entity_id", UInt64.self))
            }
            .filter { $0.col("name", String.self).eq("alice") }
        #expect(q.toSQL() ==
            "SELECT \"player\".* FROM \"player_level\" JOIN \"player\" ON " +
            "\"player_level\".\"entity_id\" = \"player\".\"entity_id\"" +
            " WHERE \"player\".\"name\" = 'alice'"
        )
    }

    @Test func rightSemijoinFromFilteredQueryCarriesLeftWhere() {
        // Pre-filter on player_level (level == 0), then join and pick player rows.
        let q = PlayerLevelRow.query()
            .filter { $0.col("level", UInt32.self).eq(0) }
            .rightSemijoin(PlayerRow.query()) { lvl, pl in
                lvl.col("entity_id", UInt64.self).joinEq(pl.col("entity_id", UInt64.self))
            }
        #expect(q.toSQL() ==
            "SELECT \"player\".* FROM \"player_level\" JOIN \"player\" ON " +
            "\"player_level\".\"entity_id\" = \"player\".\"entity_id\"" +
            " WHERE \"player_level\".\"level\" = 0"
        )
    }

    @Test func chainedFiltersOnSemiJoinAreAndCombined() {
        let q = PlayerLevelRow.query()
            .leftSemijoin(PlayerRow.query()) { lvl, pl in
                lvl.col("entity_id", UInt64.self).joinEq(pl.col("entity_id", UInt64.self))
            }
            .filter { $0.col("level", UInt32.self).gte(5) }
            .filter { $0.col("level", UInt32.self).lte(10) }
        #expect(q.toSQL() ==
            "SELECT \"player_level\".* FROM \"player_level\" JOIN \"player\" ON " +
            "\"player_level\".\"entity_id\" = \"player\".\"entity_id\"" +
            " WHERE (\"player_level\".\"level\" >= 5 AND \"player_level\".\"level\" <= 10)"
        )
    }
}
