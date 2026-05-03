//
//  StreamsChat.swift
//  quickstart-chat
//
//  Phase 10: streams-only demonstration of the SDK's modern surface —
//  no `SpacetimeDBClientDelegate`, just AsyncStreams + SubscriptionHandle
//  + Credentials.
//
//  Compare with ChatClientDelegate.swift (~400 LOC) to see what the
//  delegate-based path costs vs. the stream-based path.
//
//  Wire it up via `quickstart-chat --streams`.
//

import Foundation
import SpacetimeDB
import BSATN

actor StreamsChat {
    private let client: SpacetimeDBClient
    private let credentialsURL: URL
    private var users: [UInt256: UserRow] = [:]
    private var messages: [MessageRow] = []
    private var myIdentity: Identity?
    private var subscription: SubscriptionHandle?
    private var consumerTasks: [Task<Void, Never>] = []
    private var subscriptionReady: Bool = false

    init(host: String, db: String, credentialsURL: URL) throws {
        self.client = try SpacetimeDBClient(host: host, db: db)
        self.credentialsURL = credentialsURL
    }

    // MARK: Lifecycle

    func run(token initialToken: AuthenticationToken?) async throws {
        await client.registerTableRowDecoder(UserRow.self)
        await client.registerTableRowDecoder(MessageRow.self)

        // Spawn stream consumers BEFORE connecting so we don't miss the
        // connect / first-tick events.
        consumerTasks = [
            startConnectionConsumer(),
            startUserRowConsumer(),
            startMessageRowConsumer(),
            startReducerConsumer(),
        ]

        try await client.connect(token: initialToken)
        await waitForConnected()
        // Phase-9-fix verified: BsatnRowList parser now correctly handles
        // both FixedSize and RowOffsets size_hint variants. subscribeToAllTables
        // (alphabetical [message, user]) now works against maincloud.
        subscription = try await client.subscribeToAllTables()
        try await subscription?.applied()
        subscriptionReady = true

        print("\n✅ Subscription ready (streams mode). Type /help for commands.\n")
    }

    func shutdown() async {
        try? await subscription?.unsubscribe()
        await client.disconnect()
        for task in consumerTasks { task.cancel() }
        consumerTasks.removeAll()
    }

    var isReady: Bool { subscriptionReady }

    // MARK: Stream consumers

    private func startConnectionConsumer() -> Task<Void, Never> {
        let stream = client.connectionEvents
        return Task { [weak self] in
            for await event in stream {
                guard let self else { break }
                switch event {
                case .connected(let identity, let connectionId, let token):
                    print("🆔 Identity: \(identity.abbreviated)…  conn=\(connectionId.abbreviated)")
                    try? Credentials(token: token, identity: identity).save(to: await self.credentialsURL)
                    await self.recordIdentity(identity)
                case .reconnecting(let attempt):
                    print("🔄 Reconnecting (attempt \(attempt)/10)…")
                case .disconnected:
                    print("⚠️  Disconnected.")
                case .error(let message):
                    print("❌ \(message)")
                }
            }
        }
    }

    private func startUserRowConsumer() -> Task<Void, Never> {
        let stream = client.rowEvents(table: UserRow.tableName)
        return Task { [weak self] in
            for await event in stream {
                guard let self else { break }
                await self.applyUserRowEvent(event)
            }
        }
    }

    private func startMessageRowConsumer() -> Task<Void, Never> {
        let stream = client.rowEvents(table: MessageRow.tableName)
        return Task { [weak self] in
            for await event in stream {
                guard let self else { break }
                await self.applyMessageRowEvent(event)
            }
        }
    }

    private func startReducerConsumer() -> Task<Void, Never> {
        let stream = client.reducerEvents
        return Task {
            for await event in stream {
                let verdict: String
                switch event.status {
                case .committed:        verdict = "✅"
                case .failed(let m):    verdict = "❌ \(m)"
                case .outOfEnergy:      verdict = "⚡ out of energy"
                }
                print("🔔 \(event.reducerName) [req=\(event.requestId)] \(verdict)")
            }
        }
    }

    // MARK: Event application

    private func recordIdentity(_ identity: Identity) {
        myIdentity = identity
    }

    /// Poll `client.identity` until it's set. The IdentityToken handler
    /// in the SDK's receive loop sets it synchronously inside the actor,
    /// so polling is race-free — unlike the connectionEvents stream
    /// whose continuation registers asynchronously via a Task and may
    /// miss the first event if connect() races ahead of registration.
    private func waitForConnected() async {
        while await client.identity == nil {
            try? await Task.sleep(nanoseconds: 25_000_000)   // 25ms
        }
    }

    private func applyUserRowEvent(_ event: RowEvent) {
        switch event {
        case .inserted(let any):
            guard let user = any as? UserRow else { return }
            users[user.identity] = user
            print("   👤 + \(user.name ?? "<unnamed>") \(user.online ? "🟢" : "⚫")")
        case .deleted(let any):
            guard let user = any as? UserRow else { return }
            users.removeValue(forKey: user.identity)
            print("   👤 − \(user.name ?? "<unnamed>")")
        case .updated(let oldAny, let newAny):
            guard let oldUser = oldAny as? UserRow, let newUser = newAny as? UserRow else { return }
            users[newUser.identity] = newUser
            let oldName = oldUser.name ?? "<unnamed>"
            let newName = newUser.name ?? "<unnamed>"
            if oldName != newName {
                print("   📝 \(oldName) renamed to \(newName)")
            } else if oldUser.online != newUser.online {
                print("   👤 \(newName) went \(newUser.online ? "🟢 online" : "⚫ offline")")
            }
        }
    }

    private func applyMessageRowEvent(_ event: RowEvent) {
        switch event {
        case .inserted(let any):
            guard let msg = any as? MessageRow else { return }
            messages.append(msg)
            let senderName = users[msg.sender]?.name ?? "<unknown>"
            let isMe = (msg.sender == myIdentity?.value)
            print("   💬 [\(senderName)\(isMe ? " (you)" : "")] \(msg.text)")
        case .deleted:
            // Messages are append-only in this schema; no-op.
            break
        case .updated:
            // Messages don't have a PK so .updated is never emitted.
            break
        }
    }

    // MARK: User commands

    func sendMessage(_ text: String) async throws {
        _ = try await client.callReducer(SendMessageReducer(text: text))
    }

    func setName(_ name: String) async throws {
        _ = try await client.callReducer(SetNameReducer(userName: name))
    }

    func userCount() -> Int { users.count }
    func messageCount() -> Int { messages.count }
}
