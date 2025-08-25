# Claude Code Assistant Instructions

## Project Overview
This is a Swift SDK for SpacetimeDB, a distributed database system. The SDK enables Swift applications to connect to SpacetimeDB servers, subscribe to data changes, and execute server-side reducers.

## Important Context for AI Assistants

### Current Status
⚠️ **IMPORTANT**: Before making any changes, please read the [README.md](README.md) file, specifically the "SDK Implementation Status" section for the current state of implementation, supported features, and known limitations.

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

### Priority Roadmap Items

1. **Compression Support** (High Priority)
   - Implement Gzip decompression for `CompressibleQueryUpdate`
   - Implement Brotli decompression
   - Files: `Sources/SpacetimeDB/Server Messages/CompressibleQueryUpdate.swift`
   
   **Brotli Implementation Options:**
   
   a) **Native iOS 15+ Support** (Recommended if targeting iOS 15+):
   ```swift
   import Compression
   
   func decompressBrotli(data: Data) -> Data? {
       let decodedCapacity = 1_000_000 // Adjust based on expected size
       let decodedBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: decodedCapacity)
       defer { decodedBuffer.deallocate() }
       
       let decodedData: Data? = data.withUnsafeBytes { sourceBuffer in
           let typedPointer = sourceBuffer.bindMemory(to: UInt8.self)
           let decompressedSize = compression_decode_buffer(
               decodedBuffer, decodedCapacity,
               typedPointer.baseAddress!, data.count,
               nil, COMPRESSION_BROTLI
           )
           
           guard decompressedSize > 0 else { return nil }
           return Data(bytes: decodedBuffer, count: decompressedSize)
       }
       
       return decodedData
   }
   ```
   
   b) **Third-party library options:**
   - **SwiftBrotli**: Lightweight wrapper, SPM support, works on older iOS versions
   - **BrotliKit**: Objective-C/Swift library, CocoaPods/SPM support
   
   c) **Gzip Support** (Already available in Foundation):
   ```swift
   // iOS 13+ has native gzip support
   let decompressed = try (data as NSData).decompressed(using: .gzip) as Data
   ```
   
   **Implementation approach for CompressibleQueryUpdate:**
   ```swift
   extension CompressibleQueryUpdate {
       func decompress() throws -> Data {
           switch compression {
           case .none:
               return data
           case .gzip:
               guard let decompressed = try? (data as NSData).decompressed(using: .gzip) as Data else {
                   throw SpacetimeDBError.decompressionFailed
               }
               return decompressed
           case .brotli:
               if #available(iOS 15.0, macOS 12.0, *) {
                   guard let decompressed = decompressBrotli(data: data) else {
                       throw SpacetimeDBError.decompressionFailed
                   }
                   return decompressed
               } else {
                   throw SpacetimeDBError.brotliNotSupported
               }
           }
       }
   }
   ```

2. **Reconnection Logic** (High Priority)
   - Add automatic reconnection with exponential backoff
   - Maintain subscription state across reconnections
   - File: `Sources/SpacetimeDB/SpacetimeDBClient.swift`

3. **Missing Protocol Features** (Medium Priority)
   - Implement Unsubscribe functionality
   - Add OneOffQuery support
   - Implement server Event handling
   - Files: Check `Tags.swift` for message types

4. **Testing & Documentation** (Ongoing)
   - Add unit tests for all BSATN types
   - Create integration tests for protocol messages
   - Add code documentation with examples

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

1. Compression is not implemented (only uncompressed messages work)
2. No automatic reconnection on connection loss
3. Cannot unsubscribe from queries once subscribed
4. No heartbeat/keepalive mechanism

### Test Coverage Gaps

The SDK currently has limited test coverage (~20-30%). Major gaps include:

#### BSATN Data Types Missing Tests
- **Int256** - Completely untested
- **BSATNMessageHandler** - Message processing logic
- **SumModel protocol** - No tests at all
- **Compression enum** - Compression handling
- **BSATNError** - Error scenarios

#### Server Messages Missing Tests
- **IdentityTokenMessage** - Authentication flow
- **BsatnRowList** - Row data extraction
- **CompressibleQueryUpdate** - Compression variants
- **DatabaseUpdate** - Batch update processing
- **QueryUpdate** - Query result handling
- **TableUpdate** - Complex table parsing
- **ReducerCallInfo** - Reducer metadata

#### Client Functionality Missing Tests
- **Connection lifecycle** - connect/disconnect/reconnect
- **WebSocket handling** - All delegate methods
- **Message routing** - receiveMessage logic
- **Authentication** - Token and identity management
- **Error handling** - SpacetimeDBErrors scenarios

Priority should be given to testing Int256, server message parsing, and the connection lifecycle as these are critical for SDK reliability.

## For Contributors

Before implementing new features:
1. Check the README.md "SDK Implementation Status" section
2. Review existing code patterns in similar files
3. Test with the quickstart-chat application
4. Update README.md status section after implementing features

## Questions or Issues?

- This is a community project, not officially supported by Clockwork Labs
- SpacetimeDB documentation: https://spacetimedb.com/docs
- Review the Rust/TypeScript SDKs for reference implementation details