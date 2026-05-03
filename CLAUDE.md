# Claude Code Assistant Instructions

## Project Overview
This is a Swift SDK for SpacetimeDB, an integrated API and database system. The SDK enables Swift applications to connect to SpacetimeDB servers, subscribe to data changes, and execute server-side reducers.

## Important Context for AI Assistants

### Current Status
⚠️ **IMPORTANT**: Before making any changes, read the [README.md](README.md) file for:
- Current SDK status and maturity level
- Complete list of implemented/unimplemented features
- Known limitations and roadmap items
- Test coverage details

This document focuses on **implementation details** not covered in the README.

### Key Technical Concepts

1. **BSATN (Binary Spacetime Algebraic Type Notation)**: Binary serialization format for data exchange
   - All data types must be encoded/decoded using BSATN
   - Implementation in `Sources/BSATN/` directory
   - Large integers (UInt128, UInt256, Int128, Int256) use hex string encoding in JSON

2. **WebSocket Protocol**: All communication uses binary WebSocket messages
   - Messages have a type byte followed by BSATN-encoded payload
   - Client → Server and Server → Client message types are defined in `Sources/SpacetimeDB/Tags.swift`

3. **Table Row Decoders**: Tables require registered decoders before data can be received
   - **Recommended**: adopt the `BSATNRow` protocol on the row struct (just `init(reader:)` + `static var tableName`); register with `client.registerTableRowDecoder(MyRow.self)`. For tables with a primary key, adopt `BSATNTableWithPrimaryKey` instead — that unlocks `.updated(old:new:)` events on the per-row stream.
   - **Legacy**: implement `TableRowDecoder` directly with a `ProductModel` and a `decode(modelValues:)` method. Still supported via a default `decode(reader:)` extension that reads the AlgebraicValue first.
   - The codegen tool `spacetime-swift generate` emits `BSATNRow`/`BSATNTableWithPrimaryKey`-based files automatically.

4. **Reducers**: Server-side functions that modify database state
   - Must implement `Reducer` protocol with BSATN argument encoding
   - Called via `client.callReducer(reducer)`
   - Codegen also emits per-reducer `<Name>Reducer` structs.

5. **Subscription Management**: Clients can subscribe and unsubscribe from data changes
   - **Recommended**: `let handle = try await client.subscribe([...])` returns a `SubscriptionHandle`; await `handle.applied()` and later `handle.unsubscribe()`. Use `client.subscribeToAllTables()` to subscribe to every registered table.
   - **Legacy**: `subscribeMulti(queries:queryId:)` / `subscribe(queries:requestId:)` / `unsubscribe(queryId:)` / `unsubscribeSingle(queryId:)` still work as wire-level primitives.

6. **Event surface**: prefer AsyncStreams over the delegate.
   - `client.connectionEvents` — `.connected/.reconnecting/.disconnected/.error`
   - `client.reducerEvents` — typed `ReducerStatus` + `EnergyQuanta`
   - `client.subscriptionEvents` — `.applied/.unsubscribed/.error`
   - `client.tableEvents(named:)` — batched per-table updates
   - `client.rowEvents(table:)` — per-row events; PK-matched delete+insert pairs collapse to `.updated(old:new:)` automatically
   - `SpacetimeDBClientDelegate` still works (`connect(delegate:)` is now optional) but is legacy.

### Architecture Decisions

- **No SDK-level interpretation**: The SDK passes data to the delegate without interpreting changes — rename detection is done by the client. The streams API does it for free via PK matching when the row adopts `BSATNTableWithPrimaryKey`.
- **Batched updates**: All table updates for a transaction are batched before notifying delegate AND before fanning out to the per-table stream.
- **Offsets in BsatnRowList**: Offsets mark the START position of rows in the data blob, not the end
- **Subscription readiness**: Wait for `SubscriptionHandle.applied()` (or the legacy `onSubscribeMultiApplied` delegate call) before processing user commands. **Streams-mode trap**: subscribing before the server's `IdentityToken` arrives hangs against maincloud — always wait for `ConnectionEvent.connected` before calling `subscribe(...)`. See `Sources/quickstart-chat/StreamsChat.swift` for the canonical pattern.

### Testing Commands
When implementing new features, test with the quickstart-chat application:
```bash
swift build
./.build/debug/quickstart-chat
```

**⚠️ IMPORTANT Testing Notes:**
1. **Always test with the live client** after making changes to ensure the implementation still works with the actual SpacetimeDB server
2. **The client is interactive** - it waits for user input. Enter `/quit` to exit properly. If you just run it without input, it will appear to "hang" but it's actually waiting for commands
3. **Use echo for automated testing**: `echo "/quit" | swift run quickstart-chat` to automatically exit after connection
4. **Check connection success**: The client should show "✅ Connected to SpacetimeDB!" and receive user/message data
5. **Verify with real operations**: Test actual commands like `/name TestUser`, `/sub`, `/unsub`, and sending messages to ensure protocol changes work
6. **Maincloud target available**: The hosted db `quickstart-chat-55kji` on `wss://maincloud.spacetimedb.com` mirrors the tutorial schema (`user` PK `identity` + `message`). Run against it via:
   ```bash
   echo "/quit" | env SPACETIMEDB_HOST=https://maincloud.spacetimedb.com SPACETIMEDB_DB=quickstart-chat-55kji swift run quickstart-chat
   ```
   Connection-only is read-safe; reducer calls (`/name`, send-message) post to a shared module — get explicit user authorization before doing more than connect+subscribe.
7. **`swiftpm-testing-helper` SIGSEGV/SIGBUS on incremental builds**: when adding/removing public methods on classes consumed by the test bundle (notably `BSATNWriter`, `BSATNReader`), incremental rebuilds can leave the test xctest binary linked against a stale class layout. The helper then crashes (SIGSEGV/SIGBUS) inside `_ArrayBuffer.count.getter` when running the stale bundle. Tests themselves are fine. Workaround: `rm -rf .build && swift test` after such changes. Report this to swift.org if it reproduces on a non-macOS-26 toolchain.
8. **`BsatnRowList` wire format** (canonical): `{ size_hint: RowSizeHint, rows_data: [u8] }` where `RowSizeHint` is a tagged enum: `tag 0 = FixedSize(u16)` (every row in `rows_data` is N bytes) and `tag 1 = RowOffsets(u32 count + count*u64)` (explicit row-start offsets). `rows_data` is `u32 size + size bytes`. The original SDK parser misinterpreted `tag 0` as "empty list, no further bytes" — since fixed. The reference is `sdks/csharp/src/SpacetimeDB/ClientApi/{BsatnRowList,RowSizeHint}.g.cs` in the upstream `clockworklabs/SpacetimeDB` repo.
9. **Stream accessors are actor-isolated**: `client.connectionEvents` / `.reducerEvents` / `.subscriptionEvents` / `.tableEvents(named:)` / `.rowEvents(table:)` are actor-isolated (`await` required). Earlier nonisolated forms registered the `AsyncStream.Continuation` via a fire-and-forget `Task` and silently dropped events fired before the registration ran. The fix moved registration inside the `AsyncStream` builder closure (which runs on the actor when the property is awaited). `SubscriptionHandle.events` is similarly `async` for the same reason. `ObservableTable.init` is `async` so it can pre-register before returning.
10. **Keychain headless blocking**: `Credentials.save(service:account:)` and `.load(service:account:)` may prompt for Touch ID / password on macOS when called from unsigned binaries (incl. `swift run`, `swift test`, CI). For headless contexts, use the file-backed overloads `save(to:)` / `load(from:)`. The `--streams` quickstart-chat demo uses the file path for this reason; real iOS/macOS apps in proper bundles can use the Keychain path.

### Compression Support

The SDK supports protocol-level compression for WebSocket messages with a unified Compression enum:

```swift
let client = try SpacetimeDBClient(
    host: "http://localhost:3000",
    db: "quickstart-chat",
    compression: .brotli,  // Default compression
    debugEnabled: false
)
```

**Compression options (Sources/BSATN/Compression.swift):**
- `.none` (rawValue: 0) - No compression
- `.brotli` (rawValue: 1) - Brotli compression (requires iOS 15+/macOS 12+) - **Default and recommended**
- `.gzip` (rawValue: 2) - Full RFC 1952 support (framing stripped, raw DEFLATE payload run through Apple's `COMPRESSION_ZLIB`)

The SDK automatically handles both protocol-level compression (entire messages) and data-level compression (query updates within messages). The Compression enum provides `serverString` for WebSocket negotiation and raw values for protocol messages.

**Note:** The two previously duplicate Compression enums have been merged into a single public enum in the BSATN module.

### Priority Roadmap Items

1. **Missing Protocol Features** (Low Priority)
   - ~~Implement UnsubscribeMulti functionality~~ ✅ Completed
   - ~~Add OneOffQuery support~~ ✅ Completed
   - Implement server Event handling
   - Implement single-query Unsubscribe (vs UnsubscribeMulti)
   - Files: Check `Tags.swift` for message types

2. **Testing & Documentation** (✅ Complete)
   - ~~Add unit tests for all BSATN types~~ ✅ Completed
   - ~~Create comprehensive protocol message tests~~ ✅ Completed (92 tests)
   - Add code documentation with examples (Ongoing)

### Common Pitfalls to Avoid

1. **Don't assume libraries are available** - Always check Package.swift before using external dependencies
2. **Preserve exact indentation** when editing - The codebase uses specific formatting
3. **Don't add comments** unless specifically requested
4. **Check existing patterns** - Look at similar code before implementing new features
5. **Binary data handling** - Always use BSATN encoding/decoding, never JSON for protocol messages
6. **Verify all external links** - When adding URLs to documentation, ALWAYS test them using WebFetch to ensure they don't return 404 errors. This includes links to SpacetimeDB docs, GitHub repos, tutorials, etc.

### Development Guidelines

- **Import Statements**: Use `import SpacetimeDB` and `import BSATN` (note the Swift-style naming)
- **Error Handling**: Use descriptive error messages and proper error types from `SpacetimeDBErrors.swift`
- **Async/Await**: All network operations should use Swift's async/await patterns
- **Delegate Pattern**: Client notifications go through `SpacetimeDBClientDelegate`
- **Actor Pattern**: Use actors for thread-safe state management (see `LocalDatabase` in quickstart-chat)

### Debugging Tips

- Enable `onIncomingMessage` delegate callback to see raw message bytes
- Check message type byte (first byte) against `Tags.swift` definitions
- Use hex dump for debugging BSATN encoding issues
- The quickstart-chat app has comprehensive logging for debugging

### Debug Mode Configuration

The SDK includes a built-in debug mode that outputs detailed information about BSATN encoding/decoding and message processing:

**Enabling Debug Mode:**
```swift
let client = try SpacetimeDBClient(
    host: "http://localhost:3000",
    db: "quickstart-chat",
    debugEnabled: true  // Enable debug output
)
```

**What Debug Mode Shows:**
- BSATN reader offset tracking and byte consumption
- Hexadecimal dumps of received messages
- Detailed parsing steps for all AlgebraicValue types
- Table row decoding with field-by-field output
- Connection and subscription events
- All lines prefixed with ">>" or ">>>" for easy filtering

**Default Behavior:**
Debug mode is **disabled by default** to keep console output clean in production.

**Implementation Details:**
- Uses thread-safe `DebugConfiguration` singleton with NSLock
- Global `debugLog()` function available throughout the SDK
- Debug state propagates from SpacetimeDBClient to BSATNReader instances
- Minimal performance impact when disabled (simple nil check)

### Current Known Issues

1. ~~Gzip compression is not implemented~~ ✅ **Fixed** - Full RFC 1952 support via `MessageDecompression.gzip`
2. ~~No automatic reconnection on connection loss~~ ✅ **Fixed** - Auto-reconnect with exponential backoff
3. ~~Cannot unsubscribe from queries once subscribed~~ ✅ **Fixed** - Both single and multi unsubscribe implemented and tested
4. ~~No heartbeat/keepalive mechanism~~ ✅ **Fixed** - Native URLSessionWebSocketTask ping/pong

### Test Coverage Status

The SDK now has comprehensive test coverage (92 tests, ~85%+) including:

#### ✅ Fully Tested Components
- **BSATN Data Types**:
  - All primitive types (UInt8-256, Int8-256, Float32/64, Bool, String)
  - **Int256** - Full encoding/decoding with JSON serialization
  - Arrays, Products, and AlgebraicValues
  - Optional types via Sum types
- **Protocol Message Encoding/Decoding**:
  - **CallReducerRequest** - Reducer calls with arguments and metadata (6 tests)
  - **SubscribeMultiRequest** - Multi-query subscription requests (4 tests)
  - **UnsubscribeMultiRequest** - Multi-query unsubscription requests (5 tests)
  - **OneOffQueryRequest** - Single query execution requests (7 tests)
  - **SubscribeMultiApplied** - Subscription confirmation responses (5 tests)
  - **UnsubscribeMultiApplied** - Unsubscription confirmation responses (5 tests)
  - **OneOffQueryResponse** - Query result responses (8 tests)
- **Message Processing**:
  - **BSATNMessageHandler** - Message routing with compression support
  - **BSATNError** - Error scenarios with Equatable conformance
- **Server Messages**:
  - **IdentityTokenMessage** - Authentication flow with model values
  - **BsatnRowList** - Row data creation and management
  - **CompressibleQueryUpdate** - Uncompressed and Brotli variants
  - TransactionUpdate - Real server message parsing
- **Infrastructure**:
  - **Compression enum** - Unified enum with all options tested
  - **OptionModel** - Helper for Option sum types

#### ⚠️ Areas Still Needing Tests
- **Connection lifecycle** - WebSocket connection/disconnection flows
- **WebSocket handling** - Delegate callback interactions
- **Authentication flows** - End-to-end token management
- **Network Layer** - Connection failures, reconnection scenarios
- **Concurrent Operations** - Multiple simultaneous requests and responses

**Test Suite Notes:**
- **DO NOT USE XCTest** - use the Swift Testing framework only
- **REMOVE TRAILING BLANK SPACES** from all files
- **Test Pattern**: Each protocol message type has comprehensive tests covering:
  - Normal operation with realistic data
  - Edge cases (empty data, maximum values, unicode)
  - Binary structure validation with hex verification
  - Error scenarios and boundary conditions
- **Test Naming**: Use descriptive test method names that explain the scenario being tested
- **Success Indicators**: Include ✅ print statements for test verification messages
