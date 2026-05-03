//
//  Schema.swift
//  spacetime-swift codegen
//
//  Codable model of a SpacetimeDB module schema. Mirrors the JSON shape
//  returned by `spacetime describe <db>` / the MCP `get_schema` /
//  `GET /v1/database/<name>/schema`.
//
//  AlgebraicType is encoded as a single-key dict per variant:
//    {"U256": []}                              → primitive
//    {"String": []}                            → primitive
//    {"Product": {"elements": [...]}}          → record
//    {"Sum": {"variants": [...]}}              → tagged union
//

import Foundation

struct SchemaDoc: Decodable {
    let database: String?
    let typespace: Typespace
    let tables: [TableDef]
    let reducers: [ReducerDef]
    /// Top-level named types pointing into `typespace.types` by index.
    /// SpacetimeDB emits this array on its HTTP `/v1/database/<name>/schema`
    /// response — it's how anonymous typespace entries get human names.
    let types: [NamedType]?
}

struct NamedType: Decodable {
    let name: TypeName
    let ty: Int

    enum CodingKeys: String, CodingKey {
        case name
        case ty
    }
}

struct TypeName: Decodable {
    let scope: [String]
    let name: String
}

struct Typespace: Decodable {
    let types: [AlgebraicType]
}

struct TableDef: Decodable {
    let name: String
    let productTypeRef: Int
    let primaryKey: [Int]
    /// Whether the table is an event table (Rust's `#[table(... event)]`).
    /// Event tables have transient rows: only inserts arrive, never
    /// deletes or updates, and there is no client-side cache.
    let isEvent: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case productTypeRef = "product_type_ref"
        case primaryKey = "primary_key"
        case isEvent = "is_event"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.productTypeRef = try c.decode(Int.self, forKey: .productTypeRef)
        self.primaryKey = try c.decode([Int].self, forKey: .primaryKey)
        self.isEvent = (try? c.decodeIfPresent(Bool.self, forKey: .isEvent)) ?? false
    }
}

struct ReducerDef: Decodable {
    let name: String
    let params: ProductBody
    let lifecycle: OptionalLifecycle

    var isLifecycle: Bool { lifecycle.value != nil }
}

struct OptionalLifecycle: Decodable {
    let value: String?    // "OnConnect" / "OnDisconnect" / nil

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        if container.contains(DynamicKey(stringValue: "none")) {
            self.value = nil
            return
        }
        if let some = try? container.nestedContainer(keyedBy: DynamicKey.self, forKey: DynamicKey(stringValue: "some")) {
            // value is a single-key dict like {"OnConnect": []}
            if let key = some.allKeys.first {
                self.value = key.stringValue
                return
            }
        }
        self.value = nil
    }
}

// MARK: AlgebraicType — sum of all SpacetimeDB type variants

indirect enum AlgebraicType: Decodable {
    case bool, u8, u16, u32, u64, u128, u256
    case i8, i16, i32, i64, i128, i256
    case f32, f64
    case string
    case array(AlgebraicType)
    case product(ProductBody)
    case sum(SumBody)
    case ref(Int)              // index into typespace.types
    case unknown(String)        // future-proof

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        guard let key = container.allKeys.first?.stringValue else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "AlgebraicType missing variant key"))
        }
        switch key {
        case "Bool":   self = .bool
        case "U8":     self = .u8
        case "U16":    self = .u16
        case "U32":    self = .u32
        case "U64":    self = .u64
        case "U128":   self = .u128
        case "U256":   self = .u256
        case "I8":     self = .i8
        case "I16":    self = .i16
        case "I32":    self = .i32
        case "I64":    self = .i64
        case "I128":   self = .i128
        case "I256":   self = .i256
        case "F32":    self = .f32
        case "F64":    self = .f64
        case "String": self = .string
        case "Array":
            let element = try container.decode(AlgebraicType.self, forKey: DynamicKey(stringValue: "Array"))
            self = .array(element)
        case "Product":
            let body = try container.decode(ProductBody.self, forKey: DynamicKey(stringValue: "Product"))
            self = .product(body)
        case "Sum":
            let body = try container.decode(SumBody.self, forKey: DynamicKey(stringValue: "Sum"))
            self = .sum(body)
        case "Ref":
            let n = try container.decode(Int.self, forKey: DynamicKey(stringValue: "Ref"))
            self = .ref(n)
        default:
            self = .unknown(key)
        }
    }
}

struct ProductBody: Decodable {
    let elements: [ProductElement]
}

struct ProductElement: Decodable {
    let name: OptionalName
    let algebraicType: AlgebraicType

    enum CodingKeys: String, CodingKey {
        case name
        case algebraicType = "algebraic_type"
    }
}

struct OptionalName: Decodable {
    let value: String?
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        if let some = try? container.decode(String.self, forKey: DynamicKey(stringValue: "some")) {
            self.value = some
        } else {
            self.value = nil
        }
    }
}

struct SumBody: Decodable {
    let variants: [SumVariant]
}

struct SumVariant: Decodable {
    let name: OptionalName
    let algebraicType: AlgebraicType

    enum CodingKeys: String, CodingKey {
        case name
        case algebraicType = "algebraic_type"
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
