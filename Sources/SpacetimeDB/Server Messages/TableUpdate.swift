//
//  TableUpdate.swift
//  spacetimedb-swift-sdk
//
//  v2 wire format — see crates/client-api-messages/src/websocket/v2.rs.
//
//  TableUpdate { table_name: RawIdentifier, rows: [TableUpdateRows] }
//  TableUpdateRows = sum
//                      0 -> PersistentTable { inserts, deletes }
//                      1 -> EventTable      { events }
//
//  Note: in v1 each TableUpdate carried (table_id, table_name, num_rows,
//  [CompressibleQueryUpdate]). v2 drops table_id and num_rows; per-table
//  compression is also gone (only message-level compression remains).
//

import Foundation
import BSATN

public struct TableUpdate: Sendable {
    public let tableName: String
    public let rows: [TableUpdateRows]

    public init(tableName: String, rows: [TableUpdateRows]) {
        self.tableName = tableName
        self.rows = rows
    }

    init(reader: BSATNReader) throws {
        self.tableName = try reader.readString()
        let count: UInt32 = try reader.read()
        var rows: [TableUpdateRows] = []
        rows.reserveCapacity(Int(count))
        for _ in 0..<count {
            rows.append(try TableUpdateRows(reader: reader))
        }
        self.rows = rows
    }

    /// Flatten all `PersistentTable` inserts across the contained variants.
    public var allInserts: [Data] {
        rows.flatMap { $0.inserts }
    }

    /// Flatten all `PersistentTable` deletes across the contained variants.
    public var allDeletes: [Data] {
        rows.flatMap { $0.deletes }
    }

    /// Flatten all `EventTable` events across the contained variants.
    public var allEvents: [Data] {
        rows.flatMap { $0.events }
    }
}

public enum TableUpdateRows: Sendable {
    case persistent(inserts: BsatnRowList, deletes: BsatnRowList)
    case event(events: BsatnRowList)

    init(reader: BSATNReader) throws {
        let tag: UInt8 = try reader.read()
        switch tag {
        case 0:
            // Note v2 field order: inserts FIRST, then deletes (swapped from v1).
            let inserts = try BsatnRowList(reader: reader)
            let deletes = try BsatnRowList(reader: reader)
            self = .persistent(inserts: inserts, deletes: deletes)
        case 1:
            let events = try BsatnRowList(reader: reader)
            self = .event(events: events)
        default:
            throw BSATNError.unsupportedTag(tag)
        }
    }

    public var inserts: [Data] {
        if case let .persistent(inserts, _) = self { return inserts.rows }
        return []
    }
    public var deletes: [Data] {
        if case let .persistent(_, deletes) = self { return deletes.rows }
        return []
    }
    public var events: [Data] {
        if case let .event(events) = self { return events.rows }
        return []
    }
}

/// Set of `TableUpdate`s for one client-registered query set.
/// A `TransactionUpdate` carries one of these per affected query set.
public struct QuerySetUpdate: Sendable {
    public let querySetId: QuerySetId
    public let tables: [TableUpdate]

    init(reader: BSATNReader) throws {
        self.querySetId = try QuerySetId(reader: reader)
        let count: UInt32 = try reader.read()
        var tables: [TableUpdate] = []
        tables.reserveCapacity(Int(count))
        for _ in 0..<count {
            tables.append(try TableUpdate(reader: reader))
        }
        self.tables = tables
    }
}

/// Snapshot of resident rows used by SubscribeApplied / UnsubscribeApplied
/// (when SendDroppedRows was set) / OneOffQueryResult.
public struct QueryRows: Sendable {
    public let tables: [SingleTableRows]

    init(reader: BSATNReader) throws {
        let count: UInt32 = try reader.read()
        var tables: [SingleTableRows] = []
        tables.reserveCapacity(Int(count))
        for _ in 0..<count {
            tables.append(try SingleTableRows(reader: reader))
        }
        self.tables = tables
    }
}

public struct SingleTableRows: Sendable {
    public let tableName: String
    public let rows: BsatnRowList

    init(reader: BSATNReader) throws {
        self.tableName = try reader.readString()
        self.rows = try BsatnRowList(reader: reader)
    }
}
