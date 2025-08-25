# spacetimedb-swift-sdk
SDK to connect to SpacetimeDB from Swift

This is a community project and is not an official SDK supported by Clockwork Labs.
For more information about SpacetimeDB, visit https://spacetimedb.com

STATUS: Early development -- functional but not feature-complete.

## Installation

* Add https://github.com/ekscrypto/spacetimedb-swift-sdk.git to your Package Dependencies
* Select the app target to link against this SDK

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
- 🎯 **Subscription readiness** - Waits for data sync before accepting commands
- 🎯 **Token persistence** - Maintains identity across sessions (use `--clear-identity` to reset)

#### Available Commands
- `/help` - Show available commands
- `/name <name>` - Set your display name
- `/users` - List online users
- `/quit` - Exit the application
- Any other text sends a chat message

### Related Implementations

For comparison and reference, see the official SpacetimeDB quickstart tutorials:
- [Rust Tutorial](https://spacetimedb.com/docs/getting-started/rust-quickstart)
- [TypeScript Tutorial](https://spacetimedb.com/docs/getting-started/typescript-quickstart)
- [Server Module Source](https://github.com/clockworklabs/SpacetimeDBCircleCI/tree/master/modules/quickstart-chat)

## Usage

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

// Connect with optional saved token
try await client.connect(token: savedToken, delegate: myDelegate)
```

### Subscribing to tables
```swift
import SpacetimeDB

// Subscribe to multiple tables
try await client.subscribeMulti(
    queries: ["SELECT * FROM user", "SELECT * FROM message"], 
    queryId: 1
)
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
- **CallReducer**: Call server-side reducer functions with BSATN-encoded arguments
- **ConnectionInit**: Initial connection setup with authentication

##### ❌ Not Implemented
- **Unsubscribe**: Remove existing subscriptions
- **RegisterTimer**: Schedule recurring operations
- **OneOffQuery**: Execute single queries without subscription

#### Server → Client Messages

##### ✅ Implemented
- **IdentityToken**: Receive authentication token and identity
- **SubscribeMultiApplied**: Confirmation of multi-query subscription
- **TransactionUpdate**: Database changes from reducer execution
  - TableUpdate: Row insertions and deletions
  - DatabaseUpdate: Batch of table updates
  - ReducerCallResponse: Reducer execution status and energy usage
- **QueryUpdate**: Initial data and updates for subscribed queries
- **CompressibleQueryUpdate**: Wrapper for compression support (parsing only)

##### ⚠️ Partially Implemented
- **SubscribeApplied**: Single subscription confirmation (untested)
- **UnsubscribeApplied**: Unsubscription confirmation (untested)

##### ❌ Not Implemented
- **OneOffQueryResponse**: Response to one-off queries
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
- ❌ **Automatic Reconnection**: Manual reconnection required
- ❌ **Connection Heartbeat**: No keepalive mechanism

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

##### ❌ Not Implemented
- `onEvent`: Server event notifications
- `onOneOffQueryResult`: Query result callbacks

### Known Limitations

1. **Gzip Compression**: Gzip compression is not supported (Brotli and uncompressed work)
2. **Large Messages**: No streaming support for very large messages
3. **Reconnection**: No automatic reconnection logic
4. **Subscription Management**: Cannot unsubscribe from queries
5. **Timers**: No support for server-side scheduled operations
6. **Non-String Map Keys**: Maps/Dictionaries with non-String keys need more testing

### Roadmap / TODO

- [ ] Implement Gzip decompression
- [x] ~~Implement Brotli decompression~~ ✅ Completed
- [ ] Add automatic reconnection with exponential backoff
- [ ] Implement unsubscribe functionality
- [ ] Add one-off query support
- [ ] Implement server event handling
- [ ] Add connection heartbeat/keepalive
- [ ] Support for timer registration
- [ ] Comprehensive unit tests for all BSATN types
- [ ] Performance optimizations for large datasets
- [ ] SwiftUI property wrappers for reactive updates

## Lessons learned

* SATS-JSON supports 128-bit and 256-bit integer values which aren't supported by JSONDecoder and JSONSerialization.
* BSATN documentation is severely lacking, or at least not obvious and may require review of the Rust implementation to fully implement
* The "Quickchat Start" demo client makes uses of a the "connection_id" parameter which is marked as Internal and not to be used like this
* `tcpdump` utility has proven extremely useful in troubleshooting early connection issues
* The iOS URLSessionWebsocketTask only support "ws" and "wss" scheme, so database URLs starting with "http" and "https" have to be modified
* The SpacetimeDB server issues authentication token, or "Identity" anonymously to all requestors
* It isn't obvious how the authentication of user is expected to be done from a SpacetimeDB documentation's perspective
* Establishing an unauthenticated connection to the websocket always issues a new identity and authentication token by default
* ACL/permissions/authentication has to be performed by the reducers functions rather than the database connection itself
