//! Smoke-test module for the spacetimedb-swift-sdk Rust-parity batch.
//!
//! Exercises:
//!   - User table  -> BSATNTableWithPrimaryKey
//!   - Message     -> BSATNRow
//!   - echo (procedure)             -> typed Procedure protocol
//!   - set_name / send_message      -> reducers
//!
//! Notes:
//!   * `#[spacetimedb::procedure]` requires `features = ["unstable"]`
//!     on the spacetimedb crate (still labelled unstable as of 1.12).
//!   * ProcedureContext intentionally has no DB access — procedures
//!     are non-transactional and can't read tables. So `echo` just
//!     returns its input. That's enough to round-trip the typed
//!     Procedure protocol on the Swift side.
//!   * Event tables (`#[table(... event)]`) aren't in spacetimedb
//!     1.12 (master-only). The SDK's BSATNEventRow + wire parser are
//!     covered by unit tests + the existing TransactionUpdate fixture
//!     suite; live coverage waits for a release that exposes the flag.

use spacetimedb::{Identity, ProcedureContext, ReducerContext, Table, Timestamp};

#[spacetimedb::table(name = user, public)]
pub struct User {
    #[primary_key]
    pub identity: Identity,
    pub name: Option<String>,
    pub online: bool,
}

#[spacetimedb::table(name = message, public)]
pub struct Message {
    pub sender: Identity,
    pub sent: Timestamp,
    pub text: String,
}

#[spacetimedb::reducer(client_connected)]
pub fn on_connect(ctx: &ReducerContext) {
    if let Some(existing) = ctx.db.user().identity().find(&ctx.sender) {
        ctx.db.user().identity().update(User {
            online: true,
            ..existing
        });
    } else {
        ctx.db.user().insert(User {
            identity: ctx.sender,
            name: None,
            online: true,
        });
    }
}

#[spacetimedb::reducer(client_disconnected)]
pub fn on_disconnect(ctx: &ReducerContext) {
    if let Some(existing) = ctx.db.user().identity().find(&ctx.sender) {
        ctx.db.user().identity().update(User {
            online: false,
            ..existing
        });
    }
}

#[spacetimedb::reducer]
pub fn set_name(ctx: &ReducerContext, name: String) {
    if let Some(existing) = ctx.db.user().identity().find(&ctx.sender) {
        ctx.db.user().identity().update(User {
            name: Some(name),
            ..existing
        });
    }
}

#[spacetimedb::reducer]
pub fn send_message(ctx: &ReducerContext, text: String) {
    ctx.db.message().insert(Message {
        sender: ctx.sender,
        sent: ctx.timestamp,
        text,
    });
}

/// Echoes its input back. Stand-in for a "real" procedure since we
/// can't read tables from a ProcedureContext anyway.
#[spacetimedb::procedure]
pub fn echo(_ctx: &mut ProcedureContext, value: u64) -> u64 {
    value
}
