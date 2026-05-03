import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("Typed Query DSL")
struct QueryDSLTests {

    struct UserRow: BSATNTableWithPrimaryKey, Equatable {
        static let tableName = "user"
        let identity: Identity
        let name: String
        let online: Bool
        let level: UInt32

        var primaryKey: Identity { identity }

        init(identity: Identity, name: String, online: Bool, level: UInt32) {
            self.identity = identity
            self.name = name
            self.online = online
            self.level = level
        }

        init(reader: BSATNReader) throws {
            self.identity = try Identity(reader: reader)
            self.name = try reader.readString()
            self.online = try reader.read()
            self.level = try reader.read()
        }
    }

    // MARK: Bare table

    @Test func tableProducesSelectStar() {
        let q = QueryTable<UserRow>()
        #expect(q.toSQL() == "SELECT * FROM \"user\"")
    }

    @Test func bsatnRowQueryShorthandMatches() {
        let q = UserRow.query()
        #expect(q.toSQL() == "SELECT * FROM \"user\"")
    }

    // MARK: Filter — comparison ops

    @Test func filterEqEmitsWhereClause() {
        let sql = UserRow.query()
            .filter { $0.col("level", UInt32.self).eq(10) }
            .toSQL()
        #expect(sql == "SELECT * FROM \"user\" WHERE \"user\".\"level\" = 10")
    }

    @Test func filterStringEscapesSingleQuotes() {
        let sql = UserRow.query()
            .filter { $0.col("name", String.self).eq("O'Reilly") }
            .toSQL()
        #expect(sql == "SELECT * FROM \"user\" WHERE \"user\".\"name\" = 'O''Reilly'")
    }

    @Test func filterAllSixComparisonOps() {
        let lvl = QueryRow<UserRow>(tableAlias: "user").col("level", UInt32.self)
        #expect(lvl.eq(1).toSQL()  == "\"user\".\"level\" = 1")
        #expect(lvl.ne(1).toSQL()  == "\"user\".\"level\" != 1")
        #expect(lvl.gt(1).toSQL()  == "\"user\".\"level\" > 1")
        #expect(lvl.lt(1).toSQL()  == "\"user\".\"level\" < 1")
        #expect(lvl.gte(1).toSQL() == "\"user\".\"level\" >= 1")
        #expect(lvl.lte(1).toSQL() == "\"user\".\"level\" <= 1")
    }

    // MARK: Boolean combinators

    @Test func andCombinesPredicates() {
        let sql = UserRow.query()
            .filter {
                $0.col("level", UInt32.self).gte(5).and($0.col("online", Bool.self).isTrue)
            }
            .toSQL()
        #expect(sql == "SELECT * FROM \"user\" WHERE (\"user\".\"level\" >= 5 AND \"user\".\"online\" = TRUE)")
    }

    @Test func orCombinesPredicates() {
        let sql = UserRow.query()
            .filter {
                $0.col("name", String.self).eq("alice").or($0.col("name", String.self).eq("bob"))
            }
            .toSQL()
        #expect(sql == "SELECT * FROM \"user\" WHERE (\"user\".\"name\" = 'alice' OR \"user\".\"name\" = 'bob')")
    }

    @Test func negatedWrapsPredicate() {
        let sql = UserRow.query()
            .filter { $0.col("online", Bool.self).isTrue.negated }
            .toSQL()
        #expect(sql == "SELECT * FROM \"user\" WHERE NOT (\"user\".\"online\" = TRUE)")
    }

    @Test func chainedFiltersAreAndCombined() {
        let sql = UserRow.query()
            .filter { $0.col("level", UInt32.self).gte(5) }
            .filter { $0.col("online", Bool.self).isTrue }
            .toSQL()
        #expect(sql == "SELECT * FROM \"user\" WHERE (\"user\".\"level\" >= 5 AND \"user\".\"online\" = TRUE)")
    }

    // MARK: Bool column desugar

    @Test func boolColumnIsTrueAndIsFalse() {
        let on = QueryRow<UserRow>(tableAlias: "user").col("online", Bool.self)
        #expect(on.isTrue.toSQL() == "\"user\".\"online\" = TRUE")
        #expect(on.isFalse.toSQL() == "\"user\".\"online\" = FALSE")
    }

    // MARK: Literal encodings

    @Test func boolLiteral() {
        #expect(true.sqlEncoded == "TRUE")
        #expect(false.sqlEncoded == "FALSE")
    }

    @Test func integerLiteralsAreDecimal() {
        #expect(UInt32(42).sqlEncoded == "42")
        #expect(Int64(-7).sqlEncoded == "-7")
        #expect(UInt8(0).sqlEncoded == "0")
    }

    @Test func floatLiteralsRoundTrip() {
        #expect(Float(1.5).sqlEncoded == "1.5")
        #expect(Double(0.25).sqlEncoded == "0.25")
    }

    @Test func stringLiteralEscapesSingleQuote() {
        #expect("hello".sqlEncoded == "'hello'")
        #expect("O'Reilly".sqlEncoded == "'O''Reilly'")
        #expect("".sqlEncoded == "''")
    }

    @Test func identityLiteralIsHexPrefixed() {
        let id = Identity(hex: String(repeating: "ab", count: 32))!
        let sql = id.sqlEncoded
        #expect(sql.hasPrefix("0x"))
        #expect(sql.count == 66)   // "0x" + 64 hex chars
    }

    @Test func connectionIdLiteralIsHexPrefixed() {
        let cid = ConnectionId(UInt128(u0: 0xDEADBEEF, u1: 0))
        let sql = cid.sqlEncoded
        #expect(sql.hasPrefix("0x"))
        #expect(sql.count == 34)   // "0x" + 32 hex chars
    }

    @Test func timestampLiteralIsMicros() {
        let ts = Timestamp(microsSinceUnixEpoch: 1_700_000_000_000_000)
        #expect(ts.sqlEncoded == "1700000000000000")
    }

    @Test func timeDurationLiteralIsMicros() {
        let d = TimeDuration(seconds: 1.5)
        #expect(d.sqlEncoded == "1500000")
    }

    @Test func bigIntLiteralUsesHex() {
        let n = UInt128(u0: 0x0123456789abcdef, u1: 0)
        #expect(n.sqlEncoded == "0x00000000000000000123456789abcdef")
    }

    // MARK: Subscribe entry point — verify the query array is rendered to SQL.

    // MARK: BSATNRowQueryable / typed cols accessor

    /// Hand-rolled stand-in for what codegen emits — verifies that the
    /// `cols` accessor on `QueryRow` works when the row conforms.
    @Test func typedColsAccessorIsUsable() {
        struct UserRowQ: BSATNRowQueryable {
            static let tableName = "user"
            let identity: Identity
            let name: String?
            let online: Bool

            init(reader: BSATNReader) throws {
                self.identity = try Identity(reader: reader)
                self.name = try reader.readOptional { try reader.readString() }
                self.online = try reader.read()
            }

            struct Cols: Sendable {
                let identity: QueryColumn<UserRowQ, Identity>
                let name: QueryColumn<UserRowQ, String?>
                let online: QueryColumn<UserRowQ, Bool>
            }
            static func makeCols(tableAlias: String) -> Cols {
                Cols(
                    identity: QueryColumn(tableAlias: tableAlias, name: "identity"),
                    name: QueryColumn(tableAlias: tableAlias, name: "name"),
                    online: QueryColumn(tableAlias: tableAlias, name: "online")
                )
            }
        }

        let sql = UserRowQ.query()
            .filter { $0.cols.online.isTrue.and($0.cols.name.eq("alice")) }
            .toSQL()
        #expect(sql == "SELECT * FROM \"user\" WHERE (\"user\".\"online\" = TRUE AND \"user\".\"name\" = 'alice')")
    }

    @Test func optionalLiteralEncodesNULLForNone() {
        let none: String? = nil
        let some: String? = "alice"
        #expect(none.sqlEncoded == "NULL")
        #expect(some.sqlEncoded == "'alice'")
    }

    @Test func subscribeQueriesRendersAllToSQL() {
        // We can't talk to a server here; just verify the query array
        // round-trips into the expected SQL list. Build the same SQL
        // the wire path would forward.
        let queries: [any SpacetimeQuery] = [
            UserRow.query(),
            UserRow.query().filter { $0.col("online", Bool.self).isTrue },
        ]
        let sqls = queries.map { $0.toSQL() }
        #expect(sqls == [
            "SELECT * FROM \"user\"",
            "SELECT * FROM \"user\" WHERE \"user\".\"online\" = TRUE",
        ])
    }
}
