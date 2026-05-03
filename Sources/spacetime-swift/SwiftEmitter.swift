//
//  SwiftEmitter.swift
//  spacetime-swift codegen
//
//  Translates a parsed SpacetimeDB SchemaDoc into Swift source files.
//  Emits one file per table (BSATNRow / BSATNTableWithPrimaryKey),
//  one file per named non-table product/sum type, and one per
//  non-lifecycle reducer.
//

import Foundation

struct SwiftEmitter {
    /// Version of the `spacetime-swift` CLI. Embedded into every
    /// generated `Db.swift`; the SDK validates it against
    /// `SDKVersion.minimumCompatibleCodegenVersion` at
    /// `Db.attach(to:)` time and refuses to load codegen older than
    /// that floor. Bump in lockstep with breaking codegen-format
    /// changes.
    static let codegenVersion = "2.1.0"

    let schema: SchemaDoc

    /// Indices in `typespace.types` that are also referenced by a table's
    /// `product_type_ref`. Those become `<Name>Row` files; we don't also
    /// emit a generic struct for them.
    private var tableTypeIndices: Set<Int> {
        Set(schema.tables.map { $0.productTypeRef })
    }

    /// Map from typespace index → user-friendly Swift type name. Sourced
    /// from the schema's top-level `types` array.
    private var namedTypes: [Int: String] {
        var result: [Int: String] = [:]
        for nt in schema.types ?? [] {
            result[nt.ty] = nt.name.name
        }
        return result
    }

    /// Map of relative file path → file contents.
    func emit() -> [String: String] {
        var files: [String: String] = [:]

        // 1. Tables → <Name>Row.swift
        for table in schema.tables {
            let name = swiftTypeName(table.name) + "Row"
            files["\(name).swift"] = emitTable(table)
        }

        // 2. Named typespace entries that aren't tables → standalone
        //    Swift type files (Product → struct, Sum → enum). Skips
        //    entries with no NamedType.
        let tablesIdx = tableTypeIndices
        for nt in schema.types ?? [] where !tablesIdx.contains(nt.ty) {
            guard nt.ty < schema.typespace.types.count else { continue }
            let kind = schema.typespace.types[nt.ty]
            switch kind {
            case .product(let body):
                files["\(nt.name.name).swift"] = emitNamedProduct(name: nt.name.name, body: body)
            case .sum(let body):
                files["\(nt.name.name).swift"] = emitNamedSum(name: nt.name.name, body: body)
            default:
                continue   // primitives/refs/arrays — not emitted as standalone
            }
        }

        // 3. Reducers (skip lifecycle) → <Name>Reducer.swift
        for reducer in schema.reducers where !reducer.isLifecycle {
            let name = swiftTypeName(reducer.name) + "Reducer"
            files["\(name).swift"] = emitReducer(reducer)
        }

        // 4. Typed `Db` accessor — TS v3-style `connection.db.<table>` shape.
        //    Emitted only when there's at least one non-event table to attach
        //    (event tables don't have a client cache).
        let cacheable = schema.tables.filter { !$0.isEvent }
        if !cacheable.isEmpty {
            files["Db.swift"] = emitDb(tables: cacheable, reducers: schema.reducers.filter { !$0.isLifecycle })
        }

        return files
    }

    // MARK: Db (typed table accessor) emission

    private func emitDb(tables: [TableDef], reducers: [ReducerDef]) -> String {
        struct Field {
            let fieldName: String
            let typeName: String
        }
        let fields = tables.map { table -> Field in
            let row = swiftTypeName(table.name) + "Row"
            return Field(fieldName: swiftFieldName(table.name), typeName: row)
        }

        var src = preamble

        // Reducers — typed wrapper exposing each non-lifecycle reducer
        // as `db.reducers.<camelName>(...)`. Mirrors TS v3's
        // `connection.reducers.<camelName>(args)` shape.
        src += "/// Typed reducer accessor. Mirrors the TS v3\n"
        src += "/// `connection.reducers.<reducerName>(...)` shape — each\n"
        src += "/// method wraps the matching `<Name>Reducer` struct and\n"
        src += "/// forwards to `client.callReducer(_:)`.\n"
        src += "public struct Reducers: Sendable {\n"
        src += "    public let client: SpacetimeDBClient\n"
        src += "    public init(client: SpacetimeDBClient) { self.client = client }\n"
        for reducer in reducers {
            let typeName = swiftTypeName(reducer.name) + "Reducer"
            // Reuse the same name-collision rules SwiftEmitter applies
            // when emitting <Name>Reducer.swift so call sites match.
            let reservedReducerMembers: Set<String> = ["name", "encodeArguments"]
            let names = namedTypes
            let params = reducer.params.elements.enumerated().map { index, el -> Column in
                var fieldName = swiftFieldName(el.name.value ?? "arg\(index)")
                if reservedReducerMembers.contains(fieldName) {
                    fieldName += "Arg"
                }
                return Column(
                    index: index,
                    fieldName: fieldName,
                    kind: SwiftKind.from(el.algebraicType, namedTypes: names)
                )
            }
            let methodName = swiftFieldName(reducer.name)
            src += "\n    @discardableResult\n"
            src += "    public func \(methodName)("
            src += params.map { "\($0.fieldName): \($0.kind.swiftType)" }.joined(separator: ", ")
            src += ") async throws -> ReducerSuccess {\n"
            src += "        try await client.callReducer(\(typeName)("
            src += params.map { "\($0.fieldName): \($0.fieldName)" }.joined(separator: ", ")
            src += "))\n"
            src += "    }\n"
        }
        src += "}\n\n"

        // Db — typed table accessor + reducers + context.
        src += "/// Typed accessor for every cacheable table in this module.\n"
        src += "/// Mirrors the TS v3 `connection.db.<tableName>` shape: each\n"
        src += "/// property is a live `Table<Row>` whose cache, callbacks,\n"
        src += "/// and PK lookups are wired to the underlying client.\n"
        src += "public struct Db: Sendable {\n"
        src += "    /// Codegen version that emitted this file. The SDK\n"
        src += "    /// validates it against `SDKVersion.minimumCompatibleCodegenVersion`\n"
        src += "    /// at `attach(to:)` time and throws if the codegen is\n"
        src += "    /// older than the SDK can consume.\n"
        src += "    public static let codegenVersion: String = \"\(Self.codegenVersion)\"\n\n"
        src += "    public let client: SpacetimeDBClient\n"
        src += "    public let reducers: Reducers\n"
        for field in fields {
            src += "    public let \(field.fieldName): Table<\(field.typeName)>\n"
        }
        src += "\n    public init(client: SpacetimeDBClient, reducers: Reducers"
        for field in fields {
            src += ", \(field.fieldName): Table<\(field.typeName)>"
        }
        src += ") {\n"
        src += "        self.client = client\n"
        src += "        self.reducers = reducers\n"
        for field in fields {
            src += "        self.\(field.fieldName) = \(field.fieldName)\n"
        }
        src += "    }\n"
        src += "\n    /// Register every table row decoder on `client` and\n"
        src += "    /// instantiate the per-table caches. Awaits each\n"
        src += "    /// `Table.init` so the underlying row-event stream is\n"
        src += "    /// registered before this returns. Throws\n"
        src += "    /// `SDKVersion.Error.incompatibleCodegen` if this file\n"
        src += "    /// was emitted by a `spacetime-swift` CLI older than\n"
        src += "    /// the SDK can support.\n"
        src += "    public static func attach(to client: SpacetimeDBClient) async throws -> Db {\n"
        src += "        try SDKVersion.ensureCompatible(codegenVersion: Db.codegenVersion)\n"
        for field in fields {
            src += "        await client.registerTableRowDecoder(\(field.typeName).self)\n"
        }
        src += "        return await Db(\n"
        src += "            client: client,\n"
        src += "            reducers: Reducers(client: client),\n"
        for (i, field) in fields.enumerated() {
            let comma = i == fields.count - 1 ? "" : ","
            src += "            \(field.fieldName): Table<\(field.typeName)>(client: client)\(comma)\n"
        }
        src += "        )\n"
        src += "    }\n"
        src += "\n    /// Snapshot of the per-event context for callbacks\n"
        src += "    /// that want typed access to `db` and `reducers`\n"
        src += "    /// without capturing the surrounding scope.\n"
        src += "    public var context: EventContext<Db, Reducers> {\n"
        src += "        EventContext(client: client, db: self, reducers: reducers)\n"
        src += "    }\n"
        src += "}\n"
        return src
    }

    // MARK: Table emission

    private func emitTable(_ table: TableDef) -> String {
        guard let product = productOf(typespaceIndex: table.productTypeRef) else {
            return preamble + "// ERROR: table '\(table.name)' references missing product type \(table.productTypeRef)\n"
        }
        let names = namedTypes
        let columns = product.elements.enumerated().map { index, el -> Column in
            let kind = SwiftKind.from(el.algebraicType, namedTypes: names)
            return Column(
                index: index,
                fieldName: swiftFieldName(el.name.value ?? "field\(index)"),
                kind: kind
            )
        }

        let typeName = swiftTypeName(table.name) + "Row"
        let isPK = !table.primaryKey.isEmpty
        // Event tables take precedence: per upstream, event tables have
        // no resident rows so a primary key wouldn't be meaningful (and
        // the v10 schema validators forbid combining the two). If we
        // see both we drop PK and treat it as event.
        let conformance: String
        if table.isEvent {
            conformance = "BSATNEventRow"
        } else if isPK {
            conformance = "BSATNTableWithPrimaryKey"
        } else {
            conformance = "BSATNRow"
        }

        var src = preamble
        src += "public struct \(typeName): \(conformance), Equatable, Sendable {\n"
        src += "    public static let tableName = \"\(table.name)\"\n\n"
        for col in columns {
            src += "    public let \(col.fieldName): \(col.kind.swiftType)\n"
        }
        if !table.isEvent, isPK, let pkIndex = table.primaryKey.first, pkIndex < columns.count {
            let pk = columns[pkIndex]
            src += "\n    public var primaryKey: \(pk.kind.swiftType) { \(pk.fieldName) }\n"
        }
        src += "\n    public init(reader: BSATNReader) throws {\n"
        for col in columns {
            src += "        self.\(col.fieldName) = \(col.kind.readerExpr)\n"
        }
        src += "    }\n"
        src += "}\n"

        // Emit BSATNRowQueryable conformance: typed columns for every
        // SQL-encodable column. Unsupported types (arrays, nested
        // structs) are skipped — callers can fall back to col(_:_:).
        // The product columns we emit here use the source column name
        // (NOT the Swift field name) for the SQL identifier, since
        // that's what the server's catalog stores.
        let queryable = columns.compactMap { col -> (String, String, String)? in
            // (sqlName, swiftFieldName, queryColumnTypeParameter)
            guard let sqlType = col.kind.sqlComparableType else { return nil }
            return (product.elements[col.index].name.value ?? "field\(col.index)", col.fieldName, sqlType)
        }
        if !queryable.isEmpty {
            src += "\nextension \(typeName): BSATNRowQueryable {\n"
            src += "    public struct Cols: Sendable {\n"
            for (_, fieldName, sqlType) in queryable {
                src += "        public let \(fieldName): QueryColumn<\(typeName), \(sqlType)>\n"
            }
            src += "    }\n"
            src += "    public static func makeCols(tableAlias: String) -> Cols {\n"
            src += "        Cols(\n"
            for (i, (sqlName, fieldName, sqlType)) in queryable.enumerated() {
                let comma = i == queryable.count - 1 ? "" : ","
                src += "            \(fieldName): QueryColumn<\(typeName), \(sqlType)>(tableAlias: tableAlias, name: \"\(sqlName)\")\(comma)\n"
            }
            src += "        )\n"
            src += "    }\n"
            src += "}\n"
        }

        return src
    }

    // MARK: Reducer emission

    private func emitReducer(_ reducer: ReducerDef) -> String {
        let typeName = swiftTypeName(reducer.name) + "Reducer"
        // Protocol-reserved identifiers on `Reducer` — collisions with
        // a parameter of the same name would produce duplicate stored
        // properties. Rename by appending "Arg".
        let reservedReducerMembers: Set<String> = ["name", "encodeArguments"]
        let names = namedTypes
        let params = reducer.params.elements.enumerated().map { index, el -> Column in
            var fieldName = swiftFieldName(el.name.value ?? "arg\(index)")
            if reservedReducerMembers.contains(fieldName) {
                fieldName = fieldName + "Arg"
            }
            return Column(
                index: index,
                fieldName: fieldName,
                kind: SwiftKind.from(el.algebraicType, namedTypes: names)
            )
        }

        var src = preamble
        src += "public struct \(typeName): Reducer {\n"
        src += "    public let name = \"\(reducer.name)\"\n"
        for p in params {
            src += "    public let \(p.fieldName): \(p.kind.swiftType)\n"
        }
        src += "\n    public init("
        src += params.map { "\($0.fieldName): \($0.kind.swiftType)" }.joined(separator: ", ")
        src += ") {\n"
        for p in params {
            src += "        self.\(p.fieldName) = \(p.fieldName)\n"
        }
        src += "    }\n\n"
        src += "    public func encodeArguments(writer: BSATNWriter) throws {\n"
        for p in params {
            src += "        \(p.kind.writerStmt(varName: p.fieldName))\n"
        }
        src += "    }\n"
        src += "}\n"
        return src
    }

    // MARK: Standalone named-type emission

    /// Emit a named (non-table) Product type as a Swift struct
    /// implementing `BSATNRow`-style decoding.
    private func emitNamedProduct(name: String, body: ProductBody) -> String {
        let names = namedTypes
        let columns = body.elements.enumerated().map { index, el -> Column in
            Column(
                index: index,
                fieldName: swiftFieldName(el.name.value ?? "field\(index)"),
                kind: SwiftKind.from(el.algebraicType, namedTypes: names)
            )
        }
        var src = preamble
        src += "public struct \(name): Equatable, Sendable {\n"
        for col in columns {
            src += "    public let \(col.fieldName): \(col.kind.swiftType)\n"
        }
        src += "\n    public init(reader: BSATNReader) throws {\n"
        for col in columns {
            src += "        self.\(col.fieldName) = \(col.kind.readerExpr)\n"
        }
        src += "    }\n"
        src += "\n    public func write(to writer: BSATNWriter) throws {\n"
        for col in columns {
            src += "        \(col.kind.writerStmt(varName: col.fieldName))\n"
        }
        src += "    }\n"
        src += "}\n"
        return src
    }

    /// Emit a named Sum type as a Swift enum with associated values.
    private func emitNamedSum(name: String, body: SumBody) -> String {
        let names = namedTypes

        // Variant info: Swift case identifier + payload (nil for unit).
        struct Variant {
            let tag: Int
            let caseName: String
            let payloadKind: SwiftKind?
        }

        let variants: [Variant] = body.variants.enumerated().map { index, v in
            let raw = v.name.value ?? "case\(index)"
            let caseName = swiftFieldName(raw)
            let payload: SwiftKind?
            if case let .product(p) = v.algebraicType, p.elements.isEmpty {
                payload = nil       // unit variant
            } else {
                payload = SwiftKind.from(v.algebraicType, namedTypes: names)
            }
            return Variant(tag: index, caseName: caseName, payloadKind: payload)
        }

        var src = preamble
        src += "public enum \(name): Equatable, Sendable {\n"
        for v in variants {
            if let p = v.payloadKind {
                src += "    case \(v.caseName)(\(p.swiftType))\n"
            } else {
                src += "    case \(v.caseName)\n"
            }
        }
        src += "\n    public init(reader: BSATNReader) throws {\n"
        src += "        let tag: UInt8 = try reader.read()\n"
        src += "        switch tag {\n"
        for v in variants {
            if let p = v.payloadKind {
                src += "        case \(v.tag): self = .\(v.caseName)(\(p.readerExpr))\n"
            } else {
                src += "        case \(v.tag): self = .\(v.caseName)\n"
            }
        }
        src += "        default: throw BSATNError.invalidSumTag(tag)\n"
        src += "        }\n"
        src += "    }\n"
        src += "\n    public func write(to writer: BSATNWriter) throws {\n"
        src += "        switch self {\n"
        for v in variants {
            if let p = v.payloadKind {
                src += "        case .\(v.caseName)(let value):\n"
                src += "            writer.write(UInt8(\(v.tag)))\n"
                src += "            \(p.writerStmt(varName: "value"))\n"
            } else {
                src += "        case .\(v.caseName):\n"
                src += "            writer.write(UInt8(\(v.tag)))\n"
            }
        }
        src += "        }\n"
        src += "    }\n"
        src += "}\n"
        return src
    }

    // MARK: Helpers

    private func productOf(typespaceIndex idx: Int) -> ProductBody? {
        guard idx >= 0, idx < schema.typespace.types.count else { return nil }
        if case let .product(body) = schema.typespace.types[idx] { return body }
        return nil
    }

    private var preamble: String {
        """
        //
        //  Generated by spacetime-swift. Do not edit by hand.
        //  Source database: \(schema.database ?? "<unknown>")
        //

        import Foundation
        import BSATN
        import SpacetimeDB


        """
    }

    private struct Column {
        let index: Int
        let fieldName: String
        let kind: SwiftKind
    }
}

// MARK: Type → Swift kind mapping

indirect enum SwiftKind {
    case bool, uint8, uint16, uint32, uint64, uint128, uint256
    case int8, int16, int32, int64, int128, int256
    case float32, float64
    case string
    case identity                   // Product wrapper: __identity__: U256
    case timestamp                  // Product wrapper: __timestamp_micros_since_unix_epoch__: I64
    case connectionId               // Product wrapper: __connection_id__: U128
    case timeDuration               // Product wrapper: __time_duration_micros__: I64
    case optional(SwiftKind)
    case array(SwiftKind)
    case named(String)              // resolved type ref → Swift typename
    case unsupported(String)

    static func from(_ t: AlgebraicType, namedTypes: [Int: String] = [:]) -> SwiftKind {
        switch t {
        case .bool:   return .bool
        case .u8:     return .uint8
        case .u16:    return .uint16
        case .u32:    return .uint32
        case .u64:    return .uint64
        case .u128:   return .uint128
        case .u256:   return .uint256
        case .i8:     return .int8
        case .i16:    return .int16
        case .i32:    return .int32
        case .i64:    return .int64
        case .i128:   return .int128
        case .i256:   return .int256
        case .f32:    return .float32
        case .f64:    return .float64
        case .string: return .string
        case .array(let inner):
            return .array(SwiftKind.from(inner, namedTypes: namedTypes))
        case .product(let body):
            // Recognize SpacetimeDB's special wire-type wrappers.
            if body.elements.count == 1 {
                let el = body.elements[0]
                switch el.name.value {
                case "__identity__":                                  return .identity
                case "__timestamp_micros_since_unix_epoch__":         return .timestamp
                case "__connection_id__":                             return .connectionId
                case "__time_duration_micros__":                      return .timeDuration
                default: break
                }
            }
            return .unsupported("inline anonymous product")
        case .sum(let body):
            // Recognize Option<T>: two variants named some(T), none(unit).
            if body.variants.count == 2,
               body.variants[0].name.value == "some",
               body.variants[1].name.value == "none",
               case .product(let none) = body.variants[1].algebraicType,
               none.elements.isEmpty {
                return .optional(SwiftKind.from(body.variants[0].algebraicType, namedTypes: namedTypes))
            }
            return .unsupported("inline anonymous sum")
        case .ref(let n):
            if let name = namedTypes[n] {
                return .named(name)
            }
            return .unsupported("unnamed type ref \(n)")
        case .unknown(let name):
            return .unsupported(name)
        }
    }

    var swiftType: String {
        switch self {
        case .bool:           return "Bool"
        case .uint8:          return "UInt8"
        case .uint16:         return "UInt16"
        case .uint32:         return "UInt32"
        case .uint64:         return "UInt64"
        case .uint128:        return "UInt128"
        case .uint256:        return "UInt256"
        case .int8:           return "Int8"
        case .int16:          return "Int16"
        case .int32:          return "Int32"
        case .int64:          return "Int64"
        case .int128:         return "Int128"
        case .int256:         return "Int256"
        case .float32:        return "Float"
        case .float64:        return "Double"
        case .string:         return "String"
        case .identity:       return "Identity"
        case .timestamp:      return "Timestamp"
        case .connectionId:   return "ConnectionId"
        case .timeDuration:   return "TimeDuration"
        case .optional(let inner): return inner.swiftType + "?"
        case .array(let inner):    return "[\(inner.swiftType)]"
        case .named(let name):     return name
        case .unsupported(let n):  return "/* unsupported: \(n) */ Data"
        }
    }

    /// Returns the Swift type to use as the `V` parameter for
    /// `QueryColumn<Row, V>` when this column appears in the typed
    /// `Cols` struct, or `nil` if the column isn't SQL-comparable
    /// (arrays, nested structs, unsupported types). Optionals are
    /// supported via the `Optional: SQLLiteral` conformance.
    var sqlComparableType: String? {
        switch self {
        case .bool, .uint8, .uint16, .uint32, .uint64, .uint128, .uint256,
             .int8, .int16, .int32, .int64, .int128, .int256,
             .float32, .float64, .string,
             .identity, .timestamp, .connectionId, .timeDuration:
            return swiftType
        case .optional(let inner):
            return inner.sqlComparableType.map { "\($0)?" }
        case .array, .named, .unsupported:
            return nil
        }
    }

    /// Reader expression that decodes a single value of this kind.
    var readerExpr: String {
        switch self {
        case .bool, .uint8, .uint16, .uint32, .uint64, .uint128, .uint256,
             .int8, .int16, .int32, .int64, .int128, .int256,
             .float32, .float64:
            return "try reader.read()"
        case .string:
            return "try reader.readString()"
        case .identity:       return "try Identity(reader: reader)"
        case .timestamp:      return "try Timestamp(reader: reader)"
        case .connectionId:   return "try ConnectionId(reader: reader)"
        case .timeDuration:   return "try TimeDuration(reader: reader)"
        case .named(let name): return "try \(name)(reader: reader)"
        case .optional(let inner):
            return "try reader.readOptional { \(inner.readerExprBare) }"
        case .array(let inner):
            return "try reader.readTypedArray { \(inner.readerExprBare) }"
        case .unsupported:
            return "/* unsupported */ Data()"
        }
    }

    /// Reader expression without the `try` keyword (for nesting inside `try reader.readOptional { ... }`).
    private var readerExprBare: String {
        switch self {
        case .string: return "try reader.readString()"
        default:      return readerExpr
        }
    }

    /// Writer statement for a stored value of this kind.
    func writerStmt(varName: String) -> String {
        switch self {
        case .bool, .uint8, .uint16, .uint32, .uint64, .uint128, .uint256,
             .int8, .int16, .int32, .int64, .int128, .int256,
             .float32, .float64:
            return "writer.write(\(varName))"
        case .string:
            return "try writer.write(\(varName))"
        case .identity, .timestamp, .connectionId, .timeDuration:
            return "\(varName).write(to: writer)"
        case .named:
            return "try \(varName).write(to: writer)"
        case .optional(let inner):
            return "try writer.writeOptional(\(varName)) { \(inner.writerStmtClosure) }"
        case .array(let inner):
            return "try writer.writeTypedArray(\(varName)) { \(inner.writerStmtClosure) }"
        case .unsupported:
            return "// TODO: emit \(varName)"
        }
    }

    /// Inner statement for use inside an Optional/Array writer closure
    /// where `$0` is the per-element value. Returns a single statement.
    private var writerStmtClosure: String {
        switch self {
        case .string:                                    return "try writer.write($0)"
        case .identity, .timestamp, .connectionId, .timeDuration:
            return "$0.write(to: writer)"
        case .named:                                     return "try $0.write(to: writer)"
        case .optional(let inner):
            return "try writer.writeOptional($0) { \(inner.writerStmtClosure) }"
        case .array(let inner):
            return "try writer.writeTypedArray($0) { \(inner.writerStmtClosure) }"
        case .unsupported:                               return "/* unsupported */"
        default:
            return "writer.write($0)"
        }
    }
}

// MARK: Schema name validation

/// Reasons why a schema name is unsafe to embed into emitted Swift
/// source. SpacetimeDB itself enforces ASCII-identifier shape on
/// table, reducer, type, column, and variant names, so legitimate
/// schemas always pass; rejecting anything else closes the path
/// traversal + Swift-source-injection vector that would otherwise
/// let a malicious module owner write attacker-controlled `.swift`
/// files anywhere the dev has write access.
enum SchemaValidationError: Error, CustomStringConvertible {
    case invalidName(kind: String, value: String)
    case invalidDatabaseName(value: String)

    var description: String {
        switch self {
        case .invalidName(let kind, let value):
            return "schema \(kind) '\(value.prefix(64))' is not a valid ASCII identifier "
                + "([A-Za-z_][A-Za-z0-9_]*); spacetime-swift refuses to emit it because "
                + "doing so would allow path traversal or code injection in generated files."
        case .invalidDatabaseName(let value):
            return "schema database name '\(value.prefix(64))' contains characters outside "
                + "[A-Za-z0-9._-]; spacetime-swift refuses to emit it because doing so would "
                + "allow comment-break injection in generated files."
        }
    }
}

private func isAsciiIdentifier(_ s: String) -> Bool {
    guard !s.isEmpty else { return false }
    var first = true
    for u in s.utf8 {
        let isLetter = (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A)
        let isDigit = (u >= 0x30 && u <= 0x39)
        let isUnderscore = u == 0x5F
        if first {
            if !(isLetter || isUnderscore) { return false }
            first = false
        } else {
            if !(isLetter || isDigit || isUnderscore) { return false }
        }
    }
    return true
}

private func isSafeDatabaseName(_ s: String) -> Bool {
    guard !s.isEmpty else { return false }
    for u in s.utf8 {
        let isLetter = (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A)
        let isDigit = (u >= 0x30 && u <= 0x39)
        let isAllowedPunct = u == 0x5F || u == 0x2D || u == 0x2E    // _ - .
        if !(isLetter || isDigit || isAllowedPunct) { return false }
    }
    return true
}

func validateSchemaNames(_ schema: SchemaDoc) throws {
    func require(_ value: String, kind: String) throws {
        guard isAsciiIdentifier(value) else {
            throw SchemaValidationError.invalidName(kind: kind, value: value)
        }
    }
    if let db = schema.database, !db.isEmpty, !isSafeDatabaseName(db) {
        throw SchemaValidationError.invalidDatabaseName(value: db)
    }
    for table in schema.tables {
        try require(table.name, kind: "table name")
    }
    for reducer in schema.reducers {
        try require(reducer.name, kind: "reducer name")
        for el in reducer.params.elements {
            if let n = el.name.value { try require(n, kind: "reducer parameter name") }
        }
    }
    for nt in schema.types ?? [] {
        try require(nt.name.name, kind: "type name")
    }
    for kind in schema.typespace.types {
        switch kind {
        case .product(let body):
            for el in body.elements {
                if let n = el.name.value { try require(n, kind: "product field name") }
            }
        case .sum(let body):
            for v in body.variants {
                if let n = v.name.value { try require(n, kind: "sum variant name") }
            }
        default:
            break
        }
    }
}

// MARK: Naming helpers

private let reservedKeywords: Set<String> = [
    "actor", "associatedtype", "break", "case", "catch", "class", "continue", "default",
    "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate",
    "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let",
    "let", "nil", "operator", "private", "protocol", "public", "repeat", "return", "self",
    "static", "struct", "subscript", "switch", "throw", "throws", "true", "try", "typealias",
    "var", "where", "while", "Any", "Type"
]

func swiftTypeName(_ raw: String) -> String {
    let parts = raw.split(separator: "_", omittingEmptySubsequences: true)
    return parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
}

func swiftFieldName(_ raw: String) -> String {
    let parts = raw.split(separator: "_", omittingEmptySubsequences: true)
    guard let first = parts.first else { return "field" }
    let rest = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
    let camel = first.lowercased() + rest.joined()
    return reservedKeywords.contains(camel) ? "`\(camel)`" : camel
}
