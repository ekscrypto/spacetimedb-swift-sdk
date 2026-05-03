//
//  Tags.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-18.
//


enum Tags {
    /*
     v2 ClientMessage layout (crates/client-api-messages/src/websocket/v2.rs):

     pub enum ClientMessage {
         Subscribe(Subscribe),         // Tag 0x00
         Unsubscribe(Unsubscribe),     // Tag 0x01
         OneOffQuery(OneOffQuery),     // Tag 0x02
         CallReducer(CallReducer),     // Tag 0x03
         CallProcedure(CallProcedure), // Tag 0x04
     }
     */
    enum ClientMessage: UInt8 {
        case subscribe = 0x00
        case unsubscribe = 0x01
        case oneOffQuery = 0x02
        case callReducer = 0x03
        case callProcedure = 0x04
    }

    /*
     v2 ServerMessage layout (crates/client-api-messages/src/websocket/v2.rs):

     pub enum ServerMessage<F: WebsocketFormat> {
         InitialConnection(InitialConnection),     // Tag 0x00
         SubscribeApplied(SubscribeApplied<F>),    // Tag 0x01
         UnsubscribeApplied(UnsubscribeApplied<F>),// Tag 0x02
         SubscriptionError(SubscriptionError),     // Tag 0x03
         TransactionUpdate(TransactionUpdate<F>),  // Tag 0x04
         OneOffQueryResult(OneOffQueryResult<F>),  // Tag 0x05
         ReducerResult(ReducerResult<F>),          // Tag 0x06
         ProcedureResult(ProcedureResult),         // Tag 0x07
     }
     */
    enum ServerMessage: UInt8 {
        case initialConnection = 0x00
        case subscribeApplied = 0x01
        case unsubscribeApplied = 0x02
        case subscriptionError = 0x03
        case transactionUpdate = 0x04
        case oneOffQueryResult = 0x05
        case reducerResult = 0x06
        case procedureResult = 0x07
    }
}
