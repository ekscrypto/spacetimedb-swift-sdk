# spacetimedb-swift-sdk

[![Swift](https://github.com/ekscrypto/spacetimedb-swift-sdk/actions/workflows/swift.yml/badge.svg)](https://github.com/ekscrypto/spacetimedb-swift-sdk/actions/workflows/swift.yml)
[![Markdown Links](https://github.com/ekscrypto/spacetimedb-swift-sdk/actions/workflows/markdown-link-check.yml/badge.svg)](https://github.com/ekscrypto/spacetimedb-swift-sdk/actions/workflows/markdown-link-check.yml)
[![Swift Version](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platforms-iOS%2015.0+%20|%20macOS%2012.0+-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

SDK to connect to SpacetimeDB from Swift

This is a community project and is not an official SDK supported by Clockwork Labs.
For more information about SpacetimeDB, visit https://spacetimedb.com

STATUS: Alpha -- Core features working but protocol implementation incomplete. Production use not recommended.

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

- **Swift**: 5.9 or later
- **Platforms**:
  - iOS 15.0+ / macOS 12.0+ (for Brotli compression support)
  - iOS 13.0+ / macOS 10.15+ (without compression)
- **Xcode**: 15.0 or later (recommended)

## Sample Application: Quickstart Chat

This repository includes a fully functional chat application demonstrating SpacetimeDB integration with Swift. The sample implements the same features as the official Rust and TypeScript quickstart tutorials.

### Running the Chat Client

1. First, set up the SpacetimeDB server with the quickstart-chat module following the [official tutorial](https://spacetimedb.com/docs/getting-started)
2. Build and run the Swift client:
   ```bash
   swift build
   ./.build/debug/quickstart-chat
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
- 🎯 **Subscription management** - `/sub` and `/unsub` commands for testing subscription lifecycle
- 🎯 **Subscription readiness** - Waits for data sync before accepting commands
- 🎯 **Token persistence** - Maintains identity across sessions (use `--clear-identity` to reset)
- 🎯 **Automatic reconnection** - Reconnects with exponential backoff on connection loss
- 🎯 **Debug mode** - Enable detailed logging with `--debug` flag

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

### Creating Table Row Decoders

Before connecting to SpacetimeDB, you need to create decoders for your tables. See the **[Rust to Swift Conversion Guide](RUST_TO_SWIFT_GUIDE.md)** for detailed instructions on:
- Generating Rust module bindings
- Understanding type mappings
- Creating Swift table row decoders
- Handling optional fields and complex types

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

// Register table decoders
await client.registerTableRowDecoder(table: "user", decoder: UserRowDecoder())
await client.registerTableRowDecoder(table: "message", decoder: MessageRowDecoder())

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

// Subscribe to multiple tables
let queryId = await client.nextQueryId
try await client.subscribeMulti(
    queries: ["SELECT * FROM user", "SELECT * FROM message"], 
    queryId: queryId
)

// Later, unsubscribe from the subscription
try await client.unsubscribe(queryId: queryId)
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

// Call the reducer
let reducer = SetNameReducer(userName: "Alice")
let requestId = try await client.callReducer(reducer)
```

### Executing One-Off Queries
```swift
import SpacetimeDB

// Execute a single SQL query without subscription
let result = try await client.oneOffQuery("SELECT * FROM user", timeout: 30.0)

if let error = result.error {
    print("Query failed: \(error)")
} else {
    // Decode rows using registered table decoders
    let users: [UserRow] = await result.decodeRows(from: "user", using: client)
    
    for user in users {
        print("User: \(user.identity) \(user.name ?? "<unnamed>") \(user.online ? "online" : "offline")")
    }
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

#### Client → Server Messages

##### ✅ Implemented
- **Subscribe**: Subscribe to SQL queries
- **SubscribeMulti**: Subscribe to multiple SQL queries in one request
- **UnsubscribeMulti**: Remove existing multi-query subscriptions
- **CallReducer**: Call server-side reducer functions with BSATN-encoded arguments
- **OneOffQuery**: Execute single queries without subscription
- **ConnectionInit**: Initial connection setup with authentication

##### ❌ Not Implemented
- **Unsubscribe**: Remove single subscriptions (UnsubscribeMulti is implemented)
- **RegisterTimer**: Schedule recurring operations

#### Server → Client Messages

##### ✅ Implemented
- **IdentityToken**: Receive authentication token and identity
- **SubscribeMultiApplied**: Confirmation of multi-query subscription
- **UnsubscribeMultiApplied**: Confirmation of multi-query unsubscription
- **TransactionUpdate**: Database changes from reducer execution
  - TableUpdate: Row insertions and deletions
  - DatabaseUpdate: Batch of table updates
  - ReducerCallResponse: Reducer execution status and energy usage
- **QueryUpdate**: Initial data and updates for subscribed queries
- **CompressibleQueryUpdate**: Wrapper for compression support (parsing only)
- **OneOffQueryResponse**: Response to one-off queries

##### ⚠️ Partially Implemented
- **SubscribeApplied**: Single subscription confirmation (untested)
- **UnsubscribeApplied**: Single unsubscription confirmation (untested)

##### ❌ Not Implemented
- **Event**: Server-side event notifications

### Compression Support

- ✅ **Uncompressed**: Full support for uncompressed messages
- ✅ **Brotli**: Full support (default compression, requires iOS 15+/macOS 12+)
- ❌ **Gzip**: Not implemented (will throw error if attempted)

### WebSocket Features

- ✅ **Connection Management**: Connect, disconnect, reconnect
- ✅ **Authentication**: Token-based authentication with persistence
- ✅ **Binary Message Protocol**: BSATN encoding/decoding
- ✅ **Error Handling**: Connection errors, parsing errors, reducer errors
- ✅ **Automatic Reconnection**: Exponential backoff with configurable max attempts
- ✅ **Connection Heartbeat**: Native WebSocket ping/pong via URLSessionWebSocketTask

### Delegate Callbacks

##### ✅ Implemented
- `onConnect`: Connection established
- `onDisconnect`: Connection lost
- `onIdentityReceived`: Authentication completed
- `onError`: Error occurred
- `onIncomingMessage`: Raw message received (for debugging)
- `onTableUpdate`: Database table changes with batched updates
- `onReducerResponse`: Reducer execution results
- `onSubscribeMultiApplied`: Multi-subscription ready
- `onUnsubscribeMultiApplied`: Multi-unsubscription complete
- `onReconnecting`: Reconnection attempt in progress
- `onOneOffQueryResponse`: One-off query results

##### ❌ Not Implemented
- `onEvent`: Server event notifications

### Test Coverage

The SDK now has comprehensive unit test coverage (92 tests) for all major components:

**✅ Fully Tested (Message Protocol):**
- **Request Encoding**: CallReducer, SubscribeMulti, UnsubscribeMulti, OneOffQuery
- **Response Decoding**: SubscribeMultiApplied, UnsubscribeMultiApplied, OneOffQueryResponse
- **BSATN Types**: All primitive types, arrays, products, and AlgebraicValues
- **Large Integers**: UInt128, UInt256, Int128, Int256 with JSON encoding
- **Core Infrastructure**: IdentityToken, BsatnRowList, CompressibleQueryUpdate
- **Compression**: Unified compression enum with Brotli support
- **Message Handling**: BSATNMessageHandler with various message types and error cases
- **Binary Structure**: Exact byte-level verification of protocol messages
- **Edge Cases**: Empty data, maximum values, unicode strings, large payloads
- **Error Scenarios**: Invalid data, insufficient bytes, unsupported operations

**⚠️ Limited Testing:**
- **Protocol Flow**: End-to-end connection lifecycle and subscription management
- **Network Layer**: Connection failures, reconnection scenarios
- **Concurrent Operations**: Multiple simultaneous requests and responses

### Known Limitations

1. **Gzip Compression**: Gzip compression is not supported (Brotli and uncompressed work)
2. **Large Messages**: No streaming support for very large messages
3. **Single Subscriptions**: Cannot unsubscribe from single queries (only multi-query unsubscribe)
4. **Timers**: No support for server-side scheduled operations
5. **Non-String Map Keys**: Maps/Dictionaries with non-String keys need more testing

### Roadmap / TODO

- [ ] Implement Gzip decompression
- [x] ~~Implement Brotli decompression~~ ✅ Completed
- [x] ~~Add automatic reconnection with exponential backoff~~ ✅ Completed
- [x] ~~Add debug mode for detailed logging~~ ✅ Completed
- [x] ~~Add connection heartbeat/keepalive~~ ✅ Completed (native URLSessionWebSocketTask support)
- [x] ~~Implement multi-query unsubscribe functionality~~ ✅ Completed
- [x] ~~Add one-off query support~~ ✅ Completed
- [x] ~~Comprehensive unit tests for all protocol messages~~ ✅ Completed (92 tests)
- [ ] Implement server event handling
- [ ] Support for timer registration
- [ ] Implement single-query unsubscribe (Unsubscribe vs UnsubscribeMulti)
- [ ] Performance optimizations for large datasets
- [ ] SwiftUI property wrappers for reactive updates
- [ ] End-to-end integration tests

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
