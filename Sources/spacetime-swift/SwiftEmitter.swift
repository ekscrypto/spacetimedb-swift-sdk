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

        return files
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
