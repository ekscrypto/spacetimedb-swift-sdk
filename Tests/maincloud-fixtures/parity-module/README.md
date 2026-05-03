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

- **Event tables** (`#[table(... event)]`) — master-only as of
  spacetimedb 1.12; the Swift SDK's `BSATNEventRow` + wire-format
  parser are covered by unit tests + the existing `TransactionUpdate`
  fixture suite. Re-add the `telemetry_event` table once the flag
  ships in a released crate.
- **Procedure DB access** — `ProcedureContext` has no `.db` (procedures
  are non-transactional); `echo` therefore just round-trips its arg.
  Sufficient to exercise the Swift typed-Procedure path end-to-end.
