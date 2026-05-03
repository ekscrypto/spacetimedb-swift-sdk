# parity-module

Tiny SpacetimeDB module the Swift SDK's live smoke tests publish to a
maincloud db they own. Exercises the runtime surface added in the
Rust-parity batch:

- `User` (PK by identity) → `BSATNTableWithPrimaryKey`
- `Message` → `BSATNRow`
- `set_name(name)`, `send_message(text)` → typed `Reducer`
- `echo(value: u64) -> u64` → typed `Procedure`

## Build & publish

Requires rustc **1.90+** (spacetimedb 1.12 dependency requirement) and
the `spacetime` CLI:

```bash
cd Tests/maincloud-fixtures/parity-module
RUSTUP_TOOLCHAIN=1.90 spacetime publish -s maincloud --yes <db-name-or-identity>
```

The procedure surface needs `features = ["unstable"]` on the
spacetimedb crate (already wired in `Cargo.toml`).

## What's NOT in here

- **Procedure DB access** — `ProcedureContext` has no `.db` (procedures
  are non-transactional); `echo` therefore just round-trips its arg.
  Sufficient to exercise the Swift typed-Procedure path end-to-end.

- **Event tables** (`#[table(... event)]`) — see below.

## EVENT-FLAG-WAITING-ON-RELEASE

The Swift `BSATNEventRow` protocol, codegen support, typed
`eventRows(_:)` stream, and `TransactionUpdate` wire-format parser for
the `EventTable` rows variant are all complete and unit-tested. What's
missing is **server-side**: the `event` flag on
`#[spacetimedb::table(... event)]` lives on upstream `master` only,
not in any released `spacetimedb` crate (last checked: 1.12).

### How to check whether it has shipped

The flag's source location upstream is the bindings-macro crate. Once
this command returns a non-empty list, the flag is in a release:

```bash
cargo search spacetimedb --limit 5
# pick the latest version, then:
VER=1.13.0   # or whatever cargo search showed
cargo download "spacetimedb-bindings-macro==$VER" 2>/dev/null > /tmp/sb.crate \
  || curl -sLO "https://crates.io/api/v1/crates/spacetimedb-bindings-macro/$VER/download"
# OR after a fresh `cargo build` of any module pinning that version:
grep -rn 'sym::event\|"event" =>' \
  ~/.cargo/registry/src/*/spacetimedb-bindings-macro-$VER/src/
```

Reference for the source-of-truth attribute parsing:
`crates/bindings-macro/src/table.rs` in the upstream
`clockworklabs/SpacetimeDB` repo (look for `sym::event => { ... }`).

### What to do once it ships

1. Bump `spacetimedb` in `Cargo.toml` to the release that has it.
2. Re-add the event-table to `src/lib.rs`:

   ```rust
   #[spacetimedb::table(name = telemetry_event, public, event)]
   pub struct TelemetryEvent {
       pub kind: String,
       pub value: u64,
   }

   #[spacetimedb::reducer]
   pub fn emit_telemetry(ctx: &ReducerContext, kind: String, value: u64) {
       ctx.db.telemetry_event().insert(TelemetryEvent { kind, value });
   }
   ```

3. `RUSTUP_TOOLCHAIN=<whatever> spacetime publish -s maincloud --yes spacetime-swift-parity-test`.
4. Add a corresponding live test to
   `Tests/SpacetimeDBTests/MaincloudParitySmokeTest.swift` that:
   - Registers a `TelemetryEventRow: BSATNEventRow` decoder
   - Subscribes to `SELECT * FROM telemetry_event`
   - Calls `emit_telemetry("smoke", 1)` via a typed `Reducer`
   - Awaits one row on `client.eventRows(TelemetryEventRow.self)`
5. Remove this section + the `EVENT-FLAG-WAITING-ON-RELEASE` marker
   from this file and from the README's roadmap.

The marker `EVENT-FLAG-WAITING-ON-RELEASE` is intentionally
distinctive so a single repo grep finds every spot that needs an
update when the flag goes live.
