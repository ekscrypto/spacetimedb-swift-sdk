# spacetimedb-swift-sdk
SDK to connect to SpacetimeDB from Swift

This is a community project and is not an official SDK supported by Clockwork Labs.
For more information about SpacetimeDB, visit https://spacetimedb.com

## Installation

* Add https://github.com/ekscrypto/spacetimedb-swift-sdk.git to your Package Dependencies
* Select the app target to link against this SDK

## Usage

### Establishing a connection
```
let client = SpacetimeDBClient(
  host: "http://localhost:3000", 
  db: "quickstart-chat")
let connectionId = try await client.connect()
```
