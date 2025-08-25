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
   - Client → Server and Server → Client message types are defined in `Sources/spacetimedb-swift-sdk/Tags.swift`

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
   - Files: `Sources/spacetimedb-swift-sdk/Server Messages/CompressibleQueryUpdate.swift`

2. **Reconnection Logic** (High Priority)
   - Add automatic reconnection with exponential backoff
   - Maintain subscription state across reconnections
   - File: `Sources/spacetimedb-swift-sdk/SpacetimeDBClient.swift`

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

- **Error Handling**: Use descriptive error messages and proper error types from `SpacetimeDBErrors.swift`
- **Async/Await**: All network operations should use Swift's async/await patterns
- **Delegate Pattern**: Client notifications go through `SpacetimeDBClientDelegate`
- **Actor Pattern**: Use actors for thread-safe state management (see `LocalDatabase` in quickstart-chat)

### Debugging Tips

- Enable `onIncomingMessage` delegate callback to see raw message bytes
- Check message type byte (first byte) against `Tags.swift` definitions
- Use hex dump for debugging BSATN encoding issues
- The quickstart-chat app has comprehensive logging for debugging

### Current Known Issues

1. Compression is not implemented (only uncompressed messages work)
2. No automatic reconnection on connection loss
3. Cannot unsubscribe from queries once subscribed
4. No heartbeat/keepalive mechanism

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