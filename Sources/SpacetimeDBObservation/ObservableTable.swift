//
//  ObservableTable.swift
//  spacetimedb-swift-sdk
//
//  SwiftUI / Observation add-on. Mirrors a SpacetimeDB table's
//  rows (delivered through `client.rowEvents(table:)`) into a
//  `@Observable` collection that drives SwiftUI updates without any
//  manual diff/state plumbing.
//
//  Kept in a separate library product so the core SDK has no dependency
//  on the Observation framework. Requires iOS 17+/macOS 14+/tvOS 17+
//  /watchOS 10+ — the minimums for `import Observation`.
//

#if canImport(Observation)
import Foundation
import Observation
import SpacetimeDB
import BSATN

/// Live, SwiftUI-bindable mirror of a SpacetimeDB table.
///
/// ```swift
/// @Observable final class AppModel {
///     let users: ObservableTable<UserRow>
///     init(client: SpacetimeDBClient) {
///         self.users = ObservableTable(client: client)
///     }
/// }
///
/// // SwiftUI view
/// ForEach(Array(model.users.values), id: \.identity) { user in
///     Text(user.name ?? "<unnamed>")
/// }
/// ```
///
/// The mirror keys rows by their `BSATNTableWithPrimaryKey.primaryKey`,
/// so every `.inserted` / `.updated` / `.deleted` row event from the
/// SDK is folded into the dictionary in O(1). The consuming `Task`
/// runs until the instance is deallocated; cancellation is handled in
/// `deinit`.
@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
@MainActor
@Observable
public final class ObservableTable<Row: BSATNTableWithPrimaryKey> {
    /// Current row set keyed by primary key. Updated automatically as
    /// row events arrive. Read it from SwiftUI views to drive UI; do
    /// not mutate directly.
    public private(set) var rows: [Row.PrimaryKey: Row] = [:]

    @ObservationIgnored private let client: SpacetimeDBClient
    /// `@ObservationIgnored` skips the macro's tracking-wrapper expansion
    /// so we can mark the property `nonisolated` — required so `deinit`
    /// (arbitrary isolation) can cancel the consumer task. `Task` is
    /// `Sendable` and `.cancel()` is idempotent + thread-safe.
    @ObservationIgnored nonisolated(unsafe) private var consumerTask: Task<Void, Never>?

    /// `async` so we can await `client.rowEvents(table:)` *before* the
    /// init returns — guarantees the underlying continuation is
    /// registered with the SDK actor before any emit can race past us.
    public init(client: SpacetimeDBClient) async {
        self.client = client
        let stream = await client.rowEvents(table: Row.tableName)
        consumerTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard !Task.isCancelled, let self else { break }
                self.apply(event)
            }
        }
    }

    deinit {
        consumerTask?.cancel()
    }

    // MARK: Convenience accessors

    public var count: Int { rows.count }
    public var values: Dictionary<Row.PrimaryKey, Row>.Values { rows.values }
    public subscript(key: Row.PrimaryKey) -> Row? { rows[key] }

    private func apply(_ event: RowEvent) {
        switch event {
        case .inserted(let any):
            if let row = any as? Row { rows[row.primaryKey] = row }
        case .deleted(let any):
            if let row = any as? Row { rows.removeValue(forKey: row.primaryKey) }
        case .updated(_, let new):
            if let row = new as? Row { rows[row.primaryKey] = row }
        }
    }
}
#endif
