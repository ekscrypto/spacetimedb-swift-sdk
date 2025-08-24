//
//  Tags.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-18.
//


enum Tags {
    /*
     /// The tag recognized by the host and SDKs to mean no compression of a [`ServerMessage`].
     pub const SERVER_MSG_COMPRESSION_TAG_NONE: u8 = 0;

     /// The tag recognized by the host and SDKs to mean brotli compression  of a [`ServerMessage`].
     pub const SERVER_MSG_COMPRESSION_TAG_BROTLI: u8 = 1;

     /// The tag recognized by the host and SDKs to mean brotli compression  of a [`ServerMessage`].
     pub const SERVER_MSG_COMPRESSION_TAG_GZIP: u8 = 2;
     */
    enum Compression: UInt8 {
        case none = 0
        case brotli = 1
        case gzip = 2
    }

    /*
     pub enum ClientMessage<Args> {
     /// Request a reducer run.
     CallReducer(CallReducer<Args>),           // Tag 0x00
     /// Register SQL queries on which to receive updates.
     Subscribe(Subscribe),                     // Tag 0x01
     /// Send a one-off SQL query without establishing a subscription.
     OneOffQuery(OneOffQuery),                 // Tag 0x02
     /// Register a SQL query to to subscribe to updates.
     SubscribeSingle(SubscribeSingle),         // Tag 0x03
     SubscribeMulti(SubscribeMulti),           // Tag 0x04 ← YOUR MESSAGE!
     /// Remove a subscription to a SQL query.
     Unsubscribe(Unsubscribe),                 // Tag 0x05
     UnsubscribeMulti(UnsubscribeMulti),       // Tag 0x06
     }
     */
    enum ClientMessage: UInt8 {
        case callReducer = 0x00
        case subscribe = 0x01
        case oneOffQuery = 0x02
        case subscribeSingle = 0x03
        case subscribeMulti = 0x04
        case unsubscribe = 0x05
        case unsubscribeMulti = 0x06
    }

    /*
     pub enum ServerMessage<F: WebsocketFormat> {
     /// Informs of changes to subscribed rows.
     /// This will be removed when we switch to `SubscribeSingle`.
     InitialSubscription(InitialSubscription<F>),
     /// Upon reducer run.
     TransactionUpdate(TransactionUpdate<F>),
     /// Upon reducer run, but limited to just the table updates.
     TransactionUpdateLight(TransactionUpdateLight<F>),
     /// After connecting, to inform client of its identity.
     IdentityToken(IdentityToken),
     /// Return results to a one off SQL query.
     OneOffQueryResponse(OneOffQueryResponse<F>),
     /// Sent in response to a `SubscribeSingle` message. This contains the initial matching rows.
     SubscribeApplied(SubscribeApplied<F>),
     /// Sent in response to an `Unsubscribe` message. This contains the matching rows.
     UnsubscribeApplied(UnsubscribeApplied<F>),
     /// Communicate an error in the subscription lifecycle.
     SubscriptionError(SubscriptionError),
     /// Sent in response to a `SubscribeMulti` message. This contains the initial matching rows.
     SubscribeMultiApplied(SubscribeMultiApplied<F>),
     /// Sent in response to an `UnsubscribeMulti` message. This contains the matching rows.
     UnsubscribeMultiApplied(UnsubscribeMultiApplied<F>),
     }
     */
    enum ServerMessage: UInt8 {
        case initialSubscription = 0x00
        case transactionUpdate = 0x01
        case transactionUpdateLight = 0x02
        case identityToken = 0x03
        case oneOffQueryResponse = 0x04
        case subscribeApplied = 0x05
        case unsubscribeApplied = 0x06
        case subscriptionError = 0x07
        case subscribeMultiApplied = 0x08
        case unsubscribeMultiApplied = 0x09
    }
}
