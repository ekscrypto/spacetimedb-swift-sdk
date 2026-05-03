# spacetimedb-swift-sdk

[![Swift](https://github.com/ekscrypto/spacetimedb-swift-sdk/actions/workflows/swift.yml/badge.svg)](https://github.com/ekscrypto/spacetimedb-swift-sdk/actions/workflows/swift.yml)
[![Markdown Links](https://github.com/ekscrypto/spacetimedb-swift-sdk/actions/workflows/markdown-link-check.yml/badge.svg)](https://github.com/ekscrypto/spacetimedb-swift-sdk/actions/workflows/markdown-link-check.yml)
[![Swift Version](https://img.shields.io/badge/Swift-6.1+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platforms-iOS%2015.0+%20|%20macOS%2012.0+-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

SDK to connect to SpacetimeDB from Swift

This is a community project and is not an official SDK supported by Clockwork Labs.
For more information about SpacetimeDB, visit https://spacetimedb.com

STATUS: Alpha — speaks SpacetimeDB WebSocket protocol **v2.bsatn.spacetimedb**.
Core surface (subscribe, callReducer, callProcedure, oneOffQuery, AsyncStream events,
auto-reconnect, gzip+brotli decompression) is implemented and verified end-to-end
against `maincloud.spacetimedb.com`. Production use not recommended yet.

## Installation

### Swift Package Manager (Xcode)

1. In Xcode, open your project and navigate to **File** → **Add Package Dependencies...**
2. In the search bar, paste the repository URL:
   ```
   https://github.com/ekscrypto/spacetimedb-swift-sdk.git
   ```
3. Click **Add Package**
4. Choose the branch/version rule:
   - **Branch**: `main` (for latest updates)
   - **Version**: Use a specific version tag if available
5. Click **Add Package**
6. Select your app target when prompted to add the package products:
   - ✅ `SpacetimeDB` (required)
   - ✅ `BSATN` (required)
7. Click **Add Package**

### Swift Package Manager (Package.swift)

Add the dependency to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/ekscrypto/spacetimedb-swift-sdk.git", branch: "main")
]
```

Then add the products to your target dependencies:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "SpacetimeDB", package: "spacetimedb-swift-sdk"),
            .product(name: "BSATN", package: "spacetimedb-swift-sdk")
        ]
    )
]
```

### System Requirements

- **Swift**: 6.1 or later (the package builds in Swift 6 language mode with strict concurrency checking — the `SendableMetatype` upcoming feature is enabled on every target so generic metatype captures across actor boundaries are caught at compile time)
- **Platforms**: iOS 15.0+ / macOS 12.0+ (Brotli compression requires these minimums)
- **Xcode**: 16.3 or later (ships Swift 6.1)

## Sample Application: Quickstart Chat

This repository includes a fully functional chat application demonstrating SpacetimeDB integration with Swift. The sample implements the same features as the official Rust and TypeScript quickstart tutorials.

### Running the Chat Client

1. First, set up the SpacetimeDB server with the quickstart-chat module following the [official tutorial](https://spacetimedb.com/docs/getting-started)
2. Build and run the Swift client:
   ```bash
   swift build
   ./.build/debug/quickstart-chat
   ```

#### Command Line Options

The chat client supports several command line options for testing and debugging:

```bash
# Basic usage
./.build/debug/quickstart-chat

# Available options:
./.build/debug/quickstart-chat [OPTIONS]
```

**Available Options:**

- **`--clear-identity`** - Clears saved authentication token and creates a new anonymous identity
  - **Use case**: Testing with a fresh identity, debugging authentication issues
  - **Example**: `./.build/debug/quickstart-chat --clear-identity`

- **`--fetch-users-only`** - Connects, fetches all users via OneOffQuery, then exits (no subscription)
  - **Use case**: Testing OneOffQuery functionality, debugging server connectivity without real-time updates
  - **Example**: `./.build/debug/quickstart-chat --fetch-users-only`

- **`--no-subscribe`** - Connects without subscribing to any tables (no real-time updates)
  - **Use case**: Testing basic connection, sending reducers without receiving table updates, debugging unsubscribe behavior
  - **Behavior**: Can send messages and call reducers, but won't receive live updates from other clients
  - **Example**: `./.build/debug/quickstart-chat --no-subscribe`

- **`--streams`** - Run the streams-only demo (no `SpacetimeDBClientDelegate`)
  - **Use case**: See the AsyncStream + `SubscriptionHandle` + `Credentials` API in action.
  - **Implementation**: `Sources/quickstart-chat/StreamsChat.swift`.
  - **Example**: `./.build/debug/quickstart-chat --streams`

**Example Usage Scenarios:**

```bash
# Start fresh with a new identity
./.build/debug/quickstart-chat --clear-identity

# Test connection and fetch users without subscribing
./.build/debug/quickstart-chat --fetch-users-only

# Connect as send-only client (useful for testing unsubscribe scenarios)
./.build/debug/quickstart-chat --no-subscribe
```

### Features

The Swift chat client implements all core features from the official tutorials, plus additional enhancements:

#### Core Features (matching Rust/TypeScript)
- ✅ **Real-time messaging** - Send and receive chat messages instantly
- ✅ **User identity** - Automatic anonymous authentication with token persistence
- ✅ **Name setting** - Change your display name with `/name <name>`
- ✅ **Online presence** - Track when users join and leave
- ✅ **Message history** - View recent messages when joining
- ✅ **Input validation** - Prevents empty names and messages

#### Enhanced Features (Swift-specific)
- 🎯 **Rename detection** - Shows "User X renamed to Y" notifications
- 🎯 **Message distinction** - Your messages display differently from others
- 🎯 **User listing** - `/users` command shows all online users
- 🎯 **OneOffQuery support** - `--fetch-users-only` fetches all users without subscription
- 🎯 **Subscription management** - `/sub` and `/unsub` commands with full unsubscribe functionality
- 🎯 **Non-subscription mode** - `--no-subscribe` connects without real-time updates for testing
- 🎯 **Subscription readiness** - Waits for data sync before accepting commands
- 🎯 **Token persistence** - Maintains identity across sessions (use `--clear-identity` to reset)
- 🎯 **Automatic reconnection** - Reconnects with exponential backoff on connection loss

#### Available Commands
- `/help` - Show available commands
- `/name <name>` - Set your display name
- `/users` - List online users
- `/sub` - Subscribe to user and message updates
- `/unsub` - Unsubscribe from current subscription
- `/quit` - Exit the application
- Any other text sends a chat message

### Related Implementations

For comparison and reference, see the official SpacetimeDB quickstart tutorials:
- [Rust Tutorial](https://spacetimedb.com/docs/sdks/rust/quickstart)
- [TypeScript Tutorial](https://spacetimedb.com/docs/sdks/typescript/quickstart)
- [Server Module Tutorial](https://spacetimedb.com/docs/modules/rust/quickstart)

## Usage

### API at a glance

The SDK exposes a Swift Concurrency-first surface:

```swift
// 1. Strong types
let identity = Identity(hex: "deadbeef…")!     // wraps UInt256
let duration = TimeDuration(seconds: 1.5)
let now      = Timestamp.now

// 2. AsyncStream events (no delegate required)
for await event in await client.connectionEvents { … }                  // .connected/.reconnecting/.disconnected/.error
for await reducer in await client.reducerEvents   { … }                 // ReducerEvent { requestId, reducerName, timestamp, outcome: ReducerOutcome }
for await tableEvent in await client.tableEvents(named: "user") { … }
for await rowEvent in await client.rowEvents(table: "user") {
    // PK-matched delete+insert pairs land as .updated(old:new:) automatically
}

// 3. SubscriptionHandle with applied()/unsubscribe() futures
let sub = try await client.subscribe(["SELECT * FROM user"])
try await sub.applied()
// … work with rows …
try await sub.unsubscribe()                              // or .unsubscribe(includeDroppedRows: true)

// 4. callReducer — async/throws, returns the reducer's outcome
let success = try await client.callReducer(SetNameReducer(userName: "Alice"))
print("returned \(success.returnValue.count) bytes at \(success.timestamp)")

// 5. callProcedure — non-transactional read-only RPCs
let payload = try await client.callProcedure(name: "lookup_user", arguments: argBytes)

// 6. BSATNRow protocol — one-line table registration
struct UserRow: BSATNTableWithPrimaryKey {
    static let tableName = "user"
    let identity: UInt256
    let name: String?
    let online: Bool
    var primaryKey: UInt256 { identity }
    init(reader: BSATNReader) throws {
        self.identity = try reader.read()
        self.name = try reader.readOptional { try reader.readString() }
        self.online = try reader.read()
    }
}
await client.registerTableRowDecoder(UserRow.self)

// 7. Credentials persistence (Keychain on Apple, file fallback elsewhere)
try Credentials(token: tok, identity: id).save()
let restored = try Credentials.load()

// 8. Codegen: spacetime-swift generate
//    spacetime-swift generate --uri https://maincloud.spacetimedb.com \
//                              --db   my-module --out Sources/Generated/

// 9. Optional SwiftUI mirror (separate library product)
import SpacetimeDBObservation
@Observable final class AppModel {
    let users: ObservableTable<UserRow>
    init(client: SpacetimeDBClient) async { self.users = await ObservableTable(client: client) }
}
```

A delegate-based callback surface (`SpacetimeDBClientDelegate`) is also available; pass an instance to `connect(delegate:)` if you prefer callbacks over the streams above.

### Creating Table Row Decoders

Before connecting to SpacetimeDB, register a decoder for each table. The **`BSATNRow`** protocol shown above — one `init(reader:)` per table, registered with `client.registerTableRowDecoder(MyRow.self)` — is the standard path. The `spacetime-swift` codegen tool emits these for you from a SpacetimeDB schema JSON.

Hand-written decoders that conform to `TableRowDecoder` directly (with a `ProductModel` and a `decode(modelValues:)` method) are also supported.

### Establishing a connection
```swift
import SpacetimeDB
import BSATN

let client = try SpacetimeDBClient(
  host: "http://localhost:3000",
  db: "quickstart-chat",
  compression: .brotli,  // Default is .brotli, can also use .none
  debugEnabled: false    // Set to true for detailed logging
)

// Register table decoders (BSATNRow / BSATNTableWithPrimaryKey path)
await client.registerTableRowDecoder(UserRow.self)
await client.registerTableRowDecoder(MessageRow.self)

// Connect with optional saved token and automatic reconnection
try await client.connect(
    token: savedToken,
    timeout: 10.0,  // Connection timeout in seconds
    delegate: myDelegate,
    enableAutoReconnect: true  // Enable automatic reconnection (default)
)
```

### Subscribing to tables
```swift
import SpacetimeDB

// Subscribe to one or more SQL queries; returns a typed handle.
let sub = try await client.subscribe([
    "SELECT * FROM user",
    "SELECT * FROM message",
])

// Suspend until the server confirms with SubscribeApplied.
try await sub.applied()

// Later, unsubscribe. Pass includeDroppedRows: true to receive the
// removed rows in the corresponding UnsubscribeApplied (SendDroppedRows flag).
try await sub.unsubscribe()
```

### Calling reducers
```swift
import SpacetimeDB
import BSATN

// Define a reducer
struct SetNameReducer: Reducer {
    let name = "set_name"
    let userName: String

    func encodeArguments(writer: BSATNWriter) throws {
        try writer.write(userName)
    }
}

// Call the reducer; suspends until the server responds with ReducerResult.
do {
    let success = try await client.callReducer(SetNameReducer(userName: "Alice"))
    // success.returnValue: Data        — BSATN-encoded reducer return value
    // success.timestamp:   Date        — server-side reducer start time
    // success.transactionUpdate         — row diffs caused by this transaction
} catch ReducerCallError.executionError(let payload) {
    // typed error returned by the reducer (BSATN-encoded per its declared error type)
    print("reducer rejected the call (\(payload.count) bytes)")
} catch ReducerCallError.internalError(let message) {
    // host-level failure (panic, type error, etc.)
    print("reducer host error: \(message)")
}
```

### Calling procedures

Procedures are non-transactional read-only RPCs. Unlike reducers, they
don't commit a transaction — the response is just a return value (or
an error).

```swift
do {
    let payload = try await client.callProcedure(name: "lookup_user", arguments: argBytes)
    // payload is BSATN-encoded per the procedure's declared return type;
    // user-level errors (Result/Option) ride inside `payload`.
} catch ProcedureCallError.internalError(let message) {
    // host-level failure: unknown procedure, type error, panic, etc.
    print("procedure host error: \(message)")
}
```

### Executing One-Off Queries
```swift
import SpacetimeDB

// Execute a single SQL query without establishing a subscription.
// Returns rows grouped by table; throws on server-side errors or timeout.
do {
    let rows = try await client.oneOffQuery("SELECT * FROM user", timeout: 30.0)

    // Decode using the client's registered table decoder.
    let users: [UserRow] = await client.decodeRows(from: rows, table: "user")

    for user in users {
        print("User: \(user.identity) \(user.name ?? "<unnamed>") \(user.online ? "online" : "offline")")
    }
} catch OneOffQueryError.serverError(let message) {
    print("Query failed: \(message)")
} catch OneOffQueryError.timeout {
    print("Query timed out")
}
```

## SDK Implementation Status

### BSATN Data Types Support

#### ✅ Fully Supported Types
- **Integers**: UInt8, UInt16, UInt32, UInt64, UInt128, UInt256, Int8, Int16, Int32, Int64, Int128, Int256
- **Floating Point**: Float32 (Float), Float64 (Double)
- **Boolean**: Bool
- **Strings**: String (UTF-8)
- **Binary**: Data (byte arrays)
- **Collections**: Array<T>, Dictionary<K,V>
- **Optional**: Optional<T>
- **Custom Types**: Product types (structs), Sum types (enums with associated values)

#### ⚠️ Partially Supported
- **Tuples**: Basic support, may need testing with complex nested tuples

#### ❌ Not Yet Implemented
- **Maps with non-String keys**: Currently only String keys are fully tested

### SpacetimeDB Protocol Support

The SDK speaks the WebSocket subprotocol `v2.bsatn.spacetimedb`, matching
the upstream Rust SDK's wire format.

#### Client → Server Messages

| Tag  | Message       | Status |
|------|---------------|--------|
| 0x00 | Subscribe     | ✅ Implemented |
| 0x01 | Unsubscribe   | ✅ Implemented (with `SendDroppedRows` flag) |
| 0x02 | OneOffQuery   | ✅ Implemented |
| 0x03 | CallReducer   | ✅ Implemented |
| 0x04 | CallProcedure | ✅ Implemented |

#### Server → Client Messages

| Tag  | Message            | Status |
|------|--------------------|--------|
| 0x00 | InitialConnection  | ✅ Implemented |
| 0x01 | SubscribeApplied   | ✅ Implemented |
| 0x02 | UnsubscribeApplied | ✅ Implemented |
| 0x03 | SubscriptionError  | ✅ Implemented |
| 0x04 | TransactionUpdate  | ✅ Implemented (other-client tx; row diffs only) |
| 0x05 | OneOffQueryResult  | ✅ Implemented |
| 0x06 | ReducerResult      | ✅ Implemented (self-tx with reducer return value) |
| 0x07 | ProcedureResult    | ✅ Implemented |

### Compression Support

The protocol compresses entire `ServerMessage` frames at the WebSocket
level.

- ✅ **Uncompressed**: Full support
- ✅ **Brotli**: Full support — default; requires iOS 15+/macOS 12+
- ✅ **Gzip**: Full support — RFC 1952 framing stripped, payload run through Apple's `COMPRESSION_ZLIB`

### WebSocket Features

- ✅ **Connection Management**: Connect, disconnect, reconnect
- ✅ **Authentication**: Token-based authentication with persistence
- ✅ **Binary Message Protocol**: BSATN encoding/decoding
- ✅ **Error Handling**: Connection errors, parsing errors, reducer errors
- ✅ **Automatic Reconnection**: Exponential backoff with configurable max attempts
- ✅ **Connection Heartbeat**: Native WebSocket ping/pong via URLSessionWebSocketTask

### Delegate Callbacks

`SpacetimeDBClientDelegate` is available for callers who prefer callbacks
over the AsyncStream surface. All methods have default no-op
implementations — override only the ones you care about.

| Method | Purpose |
|--------|---------|
| `onConnect(client:)` | WebSocket connection established |
| `onDisconnect(client:)` | Connection lost |
| `onReconnecting(client:attempt:)` | Auto-reconnect about to retry |
| `onError(client:error:)` | Out-of-band error |
| `onIncomingMessage(client:message:)` | Raw frame (debugging) |
| `onIdentityReceived(client:token:identity:)` | `InitialConnection` received |
| `onSubscribeApplied(client:queryId:)` | Server confirmed Subscribe |
| `onUnsubscribeApplied(client:queryId:)` | Server confirmed Unsubscribe |
| `onSubscriptionError(client:queryId:requestId:error:)` | Subscription failed |
| `onTableUpdate(client:event:)` | Row diffs for one transaction (`TableEvent`) |
| `onReducerResponse(client:requestId:reducerName:outcome:)` | `callReducer` returned (`ReducerOutcome`) |
| `onProcedureResponse(client:requestId:procedureName:status:)` | `callProcedure` returned |

### Test Coverage

The SDK has 192 tests across 26 suites (Swift Testing framework).

**✅ Covered:**
- **Request encoding**: Subscribe, Unsubscribe (incl. `SendDroppedRows` flag), CallReducer, CallProcedure, OneOffQuery — exact byte-level binary verification
- **Response decoding**: InitialConnection, SubscribeApplied, UnsubscribeApplied (with optional `QueryRows`), SubscriptionError, TransactionUpdate, OneOffQueryResult, ReducerResult, ProcedureResult
- **Row formats**: `BsatnRowList` FixedSize and RowOffsets variants; `TableUpdateRows.persistent` and `.event` variants
- **BSATN primitive types**: all integers (incl. UInt128/UInt256/Int128/Int256), Float32/Float64, Bool, String, arrays, products, sums
- **Compression**: brotli round-trip, gzip round-trip via `/usr/bin/gzip` (incl. FNAME header handling)
- **Event surface**: AsyncStream fan-out, race-free continuation registration, per-handle event filtering, PK-matched `.updated(old:new:)` row events
- **Codegen**: emitted code type-checks against the SDK against both maincloud and a rich fixture
- **Unicode + edge cases**: empty data, max values, unicode strings, large payloads

**⚠️ Limited:**
- **Network layer**: connection failures, reconnection scenarios — verified manually against maincloud, no automated coverage
- **Concurrent operations**: multiple in-flight requests on one client

### Known Limitations

1. **No streaming for very large messages** — entire frame is buffered
2. **No SwiftUI property wrappers** beyond `ObservableTable`
3. **Non-String map keys** — Dictionaries with non-String keys are not exercised
4. **`BSATNEventRow` not live-tested** — the `event` flag for
   `#[spacetimedb::table(... event)]` is on upstream `master` but not
   yet in the released `spacetimedb` crate (≤1.12). The Swift wire
   parser, marker protocol, and codegen are all complete and unit-
   tested; we just can't publish a server module that uses the flag
   until it ships in a release. See `Tests/maincloud-fixtures/parity-module/README.md`
   for the bring-up steps once it does.

### Protocol Compatibility

The Swift SDK speaks the **`v2.bsatn.spacetimedb`** subprotocol — the
current stable wire format used by the upstream Rust SDK. The matrix
below describes what each SpacetimeDB WebSocket subprotocol offers,
sourced from `crates/client-api-messages/src/websocket/{v1,v2,v3}.rs`
and the reference Rust / TypeScript clients.

#### Subprotocol identifiers

| Identifier | Server | Used by upstream SDKs |
|------------|--------|----------------------|
| `v1.bsatn.spacetimedb` (and `v1.json.spacetimedb`) | Accepted (compat) | None — pre-1.0 only |
| `v2.bsatn.spacetimedb` | Accepted | Rust SDK, TS SDK, **Swift SDK** |
| `v3.bsatn.spacetimedb` | Preferred (offered first) | TS SDK (preferred); not Rust |

#### Feature matrix

| Feature | v1 | v2 | v3 |
|---------|----|----|----|
| Subscription model | Three message types (set-replace `Subscribe`, `SubscribeSingle`, `SubscribeMulti`) | Unified `Subscribe`/`Unsubscribe` keyed by `QuerySetId` | same as v2 |
| `SendDroppedRows` flag on Unsubscribe | ❌ (rows always returned) | ✅ | ✅ |
| `OneOffQuery` | ✅ (16-byte `messageId`) | ✅ (u32 `requestId`) | ✅ |
| `CallReducer` | ✅ — flags `Default` / `FullUpdate` / `NoSuccessNotify` | ✅ — `Default` only (`NoSuccessNotify` dropped) | ✅ |
| `CallProcedure` (read-only RPCs) | ❌ | ✅ | ✅ |
| Connection token message | `IdentityToken` | Renamed `InitialConnection` | same as v2 |
| Initial subscription delivery | Separate `InitialSubscription` server msg | Folded into `SubscribeApplied.rows: QueryRows` | same as v2 |
| Reducer result delivery | Bundled in caller's `TransactionUpdate` | Split into `ReducerResult { ReducerOutcome }` with nested `TransactionUpdate`; broadcast `TransactionUpdate` is delta-only | same as v2 |
| `TransactionUpdate` envelope | Per-reducer (status, timestamp, caller, energy, host duration, `DatabaseUpdate`) | Pure delta `[QuerySetUpdate]` keyed by `QuerySetId` | same as v2 |
| `TableUpdate` shape | `{ table_id, table_name, num_rows, [QueryUpdate] }` | `{ table_name, [TableUpdateRows] }` (`table_id`/`num_rows` removed) | same as v2 |
| Event tables (`#[spacetimedb::table(... event)]`) | ❌ | ✅ via `TableUpdateRows::EventTable` | ✅ |
| Per-table compression (`CompressableQueryUpdate`) | ✅ (Uncompressed / Brotli / Gzip wrap each `QueryUpdate`) | ❌ — message-level only | ❌ |
| Whole-message compression tags | ✅ | ✅ | ✅ |
| Energy / host duration reporting | On every `TransactionUpdate` | Only on `ReducerResult` / `ProcedureResult` | same as v2 |
| Multiple BSATN messages per WS frame | ❌ — one message per frame | ❌ — one message per frame | ✅ — a single binary payload may concatenate several `ClientMessage` / `ServerMessage` values |
| JSON wire variant | ✅ (`v1.json.spacetimedb`) | ❌ — BSATN only | ❌ — BSATN only |

#### v2 → v3 in one line

v3's schema is byte-identical to v2 (`v3.rs` re-exports `v2::ClientMessage` / `v2::ServerMessage`); the only change is a framing optimization that lets a single WebSocket binary frame carry several coalesced messages. v3 adoption only requires teaching the receive loop to loop-decode the payload — no new request or response types.

## Lessons learned

* **Why SpacetimeDB moved from Protobuf to BSATN**: The SpacetimeDB team abandoned Protobuf in favor of BSATN due to severe performance issues with the C# implementation, which introduced processing delays of up to 800ms in some scenarios. The extensive feature set of Protobuf made optimization difficult, leading to the development of BSATN as a simpler, more performant binary serialization format. (Source: [SpacetimeDB 0.11 release video](https://youtu.be/Z7MWdAEtv88?si=G65vvS1qiln7pub4))
* SATS-JSON supports 128-bit and 256-bit integer values which aren't supported by JSONDecoder and JSONSerialization.
* BSATN documentation is severely lacking, or at least not obvious and may require review of the Rust implementation to fully implement
* The "Quickchat Start" demo client makes uses of a the "connection_id" parameter which is marked as Internal and not to be used like this
* `tcpdump` utility has proven extremely useful in troubleshooting early connection issues
* The iOS URLSessionWebsocketTask only support "ws" and "wss" scheme, so database URLs starting with "http" and "https" have to be modified
* The SpacetimeDB server issues authentication token, or "Identity" anonymously to all requestors
* It isn't obvious how the authentication of user is expected to be done from a SpacetimeDB documentation's perspective
* Establishing an unauthenticated connection to the websocket always issues a new identity and authentication token by default
* ACL/permissions/authentication has to be performed by the reducers functions rather than the database connection itself
