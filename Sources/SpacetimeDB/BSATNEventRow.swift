//
//  BSATNEventRow.swift
//  spacetimedb-swift-sdk
//
//  Marker protocol for event tables — tables whose rows are transient
//  and never persisted in the client cache. Mirrors Rust's `EventTable`
//  trait (sdks/rust/src/table.rs):
//
//      Event table rows are delivered as inserts but are not stored;
//      only `on_insert` callbacks fire, and `count`/`iter` always
//      reflect an empty table.
//
//  On the wire, server-side `#[spacetimedb::table(... event)]` tables
//  send their rows in the `TableUpdateRows::EventTable(EventTableRows)`
//  variant (vs `PersistentTable { deletes, inserts }`). The Swift
//  receive loop already routes that variant to inserts only, so this
//  file's job is just to:
//    1. give callers a typed marker so codegen can emit the right
//       conformance, and
//    2. expose a typed insert-only stream that filters & casts.
//

import Foundation
import BSATN

/// Adopt on a row struct whose backing table is declared `event` on the
/// server. The contract: only `.inserted` events will ever be observed
/// for this table — the SDK will never produce `.deleted` or `.updated`
/// `RowEvent`s for it.
///
/// Use `await client.eventRows(MyEvent.self)` to receive a typed
/// `AsyncStream<MyEvent>`. You can also subscribe via the generic
/// `client.rowEvents(table:)` and pattern match on `.inserted`.
public protocol BSATNEventRow: BSATNRow {}

public extension SpacetimeDBClient {
    /// Typed insert-only stream for an event-table row type. Each
    /// emission is a single decoded row, in arrival order. Multiple
    /// rows in the same transaction are emitted back-to-back.
    ///
    /// Actor-isolated for the same reason as `rowEvents(table:)`: the
    /// continuation must be registered in the per-table dictionary
    /// synchronously, before any caller can trigger an `emit(...)`.
    /// Awaiting the call lets the registration happen on the actor;
    /// without `async` we'd race emissions against a hop into the actor.
    func eventRows<R: BSATNEventRow>(_ type: R.Type) -> AsyncStream<R> {
        AsyncStream { typedContinuation in
            // Register a forwarding RowEvent continuation directly into
            // the existing per-row dictionary. Filtering (insert-only,
            // typed cast) happens inside the row continuation's own
            // `yield` path — no separate Task, no second AsyncStream,
            // no race between Task scheduling and the next emission.
            let id = UUID()
            let forwarder = TypedRowForwarder<R>(typed: typedContinuation)
            self.rowContinuations[R.tableName, default: [:]][id] = forwarder.continuation
            let weakSelf = WeakEventClient(self)
            let tableName = R.tableName
            typedContinuation.onTermination = { @Sendable [weakSelf] _ in
                forwarder.finish()
                Task { [weakSelf] in
                    await weakSelf.client?.unregisterRowContinuation(id: id, tableName: tableName)
                }
            }
        }
    }
}

/// Pairs a real `AsyncStream<RowEvent>.Continuation` (which the actor
/// stores in `rowContinuations`) with a forwarding `Task` that drains
/// it into the typed `AsyncStream<R>.Continuation`. The forwarding task
/// is started eagerly at init so it's already awaiting before the
/// continuation is registered with the actor.
private final class TypedRowForwarder<R: BSATNRow>: @unchecked Sendable {
    let continuation: AsyncStream<RowEvent>.Continuation
    private let stream: AsyncStream<RowEvent>
    private let task: Task<Void, Never>

    init(typed: AsyncStream<R>.Continuation) {
        var capturedCont: AsyncStream<RowEvent>.Continuation!
        self.stream = AsyncStream<RowEvent> { c in capturedCont = c }
        self.continuation = capturedCont
        let stream = self.stream
        self.task = Task {
            for await event in stream {
                guard case .inserted(let any) = event, let row = any as? R else { continue }
                typed.yield(row)
            }
            typed.finish()
        }
    }

    func finish() {
        continuation.finish()
        task.cancel()
    }
}

private struct WeakEventClient: @unchecked Sendable {
    weak var client: SpacetimeDBClient?
    init(_ client: SpacetimeDBClient) { self.client = client }
}
