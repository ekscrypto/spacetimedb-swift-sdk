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
   - Must implement `TableRowDecoder` protocol
   - Register before connecting: `client.registerTableRowDecoder(table: "name", decoder: MyDecoder())`

4. **Reducers**: Server-side functions that modify database state
   - Must implement `Reducer` protocol with BSATN argument encoding
   - Called via `client.callReducer(reducer)`

### Architecture Decisions

- **No SDK-level interpretation**: The SDK passes data to the client delegate without interpreting changes (e.g., rename detection is done by the client, not the SDK)
- **Batched updates**: All table updates for a transaction are batched before notifying the delegate
- **Offsets in BsatnRowList**: Offsets mark the START position of rows in the data blob, not the end
- **Subscription readiness**: Clients should wait for `onSubscribeMultiApplied` before processing user commands

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
5. **Verify with real operations**: Test actual commands like `/name TestUser` and sending messages to ensure protocol changes work

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
- `.brotli` (rawValue: 2) - Brotli compression (requires iOS 15+/macOS 12+) - **Default and recommended**
- `.gzip` (rawValue: 1) - Not currently supported (will throw an error)

The SDK automatically handles both protocol-level compression (entire messages) and data-level compression (query updates within messages). The Compression enum provides `serverString` for WebSocket negotiation and raw values for protocol messages.

**Note:** The two previously duplicate Compression enums have been merged into a single public enum in the BSATN module.

### Priority Roadmap Items

1. **Missing Protocol Features** (Medium Priority)
   - Implement Unsubscribe functionality
   - Add OneOffQuery support
   - Implement server Event handling
   - Files: Check `Tags.swift` for message types

2. **Testing & Documentation** (✅ Mostly Complete)
   - ~~Add unit tests for all BSATN types~~ ✅ Completed
   - ~~Create integration tests for protocol messages~~ ✅ Completed
   - Add code documentation with examples (Ongoing)

### Common Pitfalls to Avoid

1. **Don't assume libraries are available** - Always check Package.swift before using external dependencies
2. **Preserve exact indentation** when editing - The codebase uses specific formatting
3. **Don't add comments** unless specifically requested
4. **Check existing patterns** - Look at similar code before implementing new features
5. **Binary data handling** - Always use BSATN encoding/decoding, never JSON for protocol messages

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

1. **Gzip compression** is not implemented (Brotli and uncompressed messages work)
2. ~~No automatic reconnection on connection loss~~ ✅ **Fixed** - Auto-reconnect with exponential backoff
3. **Cannot unsubscribe** from queries once subscribed
4. ~~No heartbeat/keepalive mechanism~~ ✅ **Fixed** - Native URLSessionWebSocketTask ping/pong

### Test Coverage Status

The SDK now has comprehensive test coverage (~70%+) including:

#### ✅ Fully Tested Components
- **BSATN Data Types**:
  - All primitive types (UInt8-256, Int8-256, Float32/64, Bool, String)
  - **Int256** - Full encoding/decoding with JSON serialization
  - Arrays, Products, and AlgebraicValues
  - Optional types via Sum types
- **Message Processing**:
  - **BSATNMessageHandler** - Message routing with compression support
  - **BSATNError** - Error scenarios with Equatable conformance
- **Server Messages**:
  - **IdentityTokenMessage** - Authentication flow with model values
  - **BsatnRowList** - Row data creation and management
  - **CompressibleQueryUpdate** - Uncompressed and Brotli variants
  - TransactionUpdate - Real server message parsing
  - SubscribeMultiApplied - Table ID validation
- **Infrastructure**:
  - **Compression enum** - Unified enum with all options tested
  - **OptionModel** - Helper for Option sum types

#### ⚠️ Areas Still Needing Tests
- **Connection lifecycle** - WebSocket connection/disconnection flows
- **WebSocket handling** - Delegate callback interactions
- **Authentication flows** - End-to-end token management
- **DatabaseUpdate** - Complex batch operations
- **QueryUpdate** - Comprehensive query result scenarios

The SDK uses both XCTest (legacy tests) and Swift Testing framework (new tests) for comprehensive coverage.
