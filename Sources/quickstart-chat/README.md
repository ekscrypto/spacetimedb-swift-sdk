# Quickstart Chat (Swift)

A fully functional chat application demonstrating SpacetimeDB integration with
Swift. Implements the same features as the official Rust and TypeScript
quickstart tutorials.

## Running

1. Set up the SpacetimeDB server with the quickstart-chat module by following
   the [official tutorial](https://spacetimedb.com/docs/).
2. Build and run the Swift client from the repository root:
   ```bash
   swift build
   ./.build/debug/quickstart-chat
   ```

## Command line options

```bash
./.build/debug/quickstart-chat [OPTIONS]
```

- **`--clear-identity`** — Clears saved authentication token and creates a new
  anonymous identity. Useful for testing with a fresh identity or debugging
  authentication issues.
- **`--fetch-users-only`** — Connects, fetches all users via OneOffQuery, then
  exits (no subscription). Useful for testing OneOffQuery functionality and
  debugging server connectivity without real-time updates.
- **`--no-subscribe`** — Connects without subscribing to any tables (no
  real-time updates). Can send messages and call reducers, but won't receive
  live updates from other clients. Useful for testing basic connection and
  unsubscribe behavior.
- **`--streams`** — Run the streams-only demo (no `SpacetimeDBClientDelegate`).
  Demonstrates the AsyncStream + `SubscriptionHandle` + `Credentials` API.
  Implementation lives in `StreamsChat.swift`.

Examples:

```bash
# Start fresh with a new identity
./.build/debug/quickstart-chat --clear-identity

# Test connection and fetch users without subscribing
./.build/debug/quickstart-chat --fetch-users-only

# Connect as send-only client (useful for testing unsubscribe scenarios)
./.build/debug/quickstart-chat --no-subscribe
```

## Features

### Core (matching Rust/TypeScript)
- ✅ **Real-time messaging** — Send and receive chat messages instantly
- ✅ **User identity** — Automatic anonymous authentication with token persistence
- ✅ **Name setting** — Change your display name with `/name <name>`
- ✅ **Online presence** — Track when users join and leave
- ✅ **Message history** — View recent messages when joining
- ✅ **Input validation** — Prevents empty names and messages

### Swift-specific enhancements
- 🎯 **Rename detection** — Shows "User X renamed to Y" notifications
- 🎯 **Message distinction** — Your messages display differently from others
- 🎯 **User listing** — `/users` command shows all online users
- 🎯 **OneOffQuery support** — `--fetch-users-only` fetches all users without subscription
- 🎯 **Subscription management** — `/sub` and `/unsub` commands with full unsubscribe functionality
- 🎯 **Non-subscription mode** — `--no-subscribe` connects without real-time updates for testing
- 🎯 **Subscription readiness** — Waits for data sync before accepting commands
- 🎯 **Token persistence** — Maintains identity across sessions (use `--clear-identity` to reset)
- 🎯 **Automatic reconnection** — Reconnects with exponential backoff on connection loss

## Available commands
- `/help` — Show available commands
- `/name <name>` — Set your display name
- `/users` — List online users
- `/sub` — Subscribe to user and message updates
- `/unsub` — Unsubscribe from current subscription
- `/quit` — Exit the application
- Any other text sends a chat message

## Related implementations

For comparison and reference, see the official SpacetimeDB quickstart tutorials
(each Rust quickstart covers both the server module and the client SDK):

- [Rust Quickstart](https://spacetimedb.com/docs/quickstarts/rust)
- [TypeScript Quickstart](https://spacetimedb.com/docs/quickstarts/typescript)
