//
//  ChatClientDelegate.swift
//  spacetimedb-swift-sdk
//
//  Delegate-based path of the quickstart-chat demo. The streams-based
//  path lives in `StreamsChat.swift` (run via `quickstart-chat --streams`).
//

import Foundation
import SpacetimeDB
import BSATN

final class ChatClientDelegate: SpacetimeDBClientDelegate, @unchecked Sendable {
    private let database = LocalDatabase()
    private var myIdentity: UInt256? = nil
    private var subscriptionReady: Bool = false
    private var subscription: SubscriptionHandle? = nil
    private let autoSubscribe: Bool
    private var isIntentionalDisconnect: Bool = false

    init(autoSubscribe: Bool = true) {
        self.autoSubscribe = autoSubscribe
    }

    // MARK: Connection lifecycle

    func onConnect(client: SpacetimeDBClient) async {
        print("\n✅ Connected to SpacetimeDB!")
        subscriptionReady = false
        subscription = nil
        await database.clear()
    }

    func onIdentityReceived(client: SpacetimeDBClient, token: String, identity: UInt256) async {
        print("🆔 Identity received: \(identity.description)...")
        TokenStorage.save(token: token, identity: identity)
        myIdentity = identity

        if autoSubscribe {
            do {
                _ = try await subscribe(client: client)
            } catch {
                print("❌ Failed to auto-subscribe: \(error)")
            }
        } else {
            print("🚫 Auto-subscription disabled")
        }
    }

    func onReconnecting(client: SpacetimeDBClient, attempt: Int) async {
        print("\n🔄 Attempting to reconnect... (attempt \(attempt)/10)")
    }

    func onError(client: SpacetimeDBClient, error: any Error) async {
        print("\n❌ Error: \(error)")
    }

    func onDisconnect(client: SpacetimeDBClient) async {
        if !isIntentionalDisconnect {
            print("\n⚠️  Connection lost! Will attempt to reconnect automatically...")
        }
        subscriptionReady = false
        subscription = nil
        isIntentionalDisconnect = false
    }

    func onIncomingMessage(client: SpacetimeDBClient, message: Data) async {
        // Quiet by default; uncomment for protocol-level debugging.
        // print("📨 Received message (\(message.count) bytes)")
    }

    // MARK: Subscription lifecycle

    func onSubscribeApplied(client: SpacetimeDBClient, queryId: UInt32) async {
        print("✅ Subscription applied (queryId: \(queryId))")
        subscriptionReady = true

        let userCount = await database.getUserCount()
        let messageCount = await database.getMessageCount()
        print("📊 Database state: \(userCount) users, \(messageCount) messages")

        // Display recent message history
        let messages = await database.getAllMessages()
        let recentMessages = messages.suffix(10)
        if !recentMessages.isEmpty {
            print("\n📜 Recent message history:")
            let users = await database.getAllUsers()
            for message in recentMessages {
                let senderName = users.first(where: { $0.identity == message.sender })?.name ?? "Unknown"
                let date = Date(timeIntervalSince1970: Double(message.sent) / 1_000_000.0)
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                let timeString = formatter.string(from: date)
                if message.sender == myIdentity {
                    print("   [\(timeString)] You: \(message.text)")
                } else {
                    print("   [\(timeString)] \(senderName): \(message.text)")
                }
            }
        }
    }

    func onUnsubscribeApplied(client: SpacetimeDBClient, queryId: UInt32) async {
        print("✅ Unsubscribe applied (queryId: \(queryId))")
        subscriptionReady = false
        subscription = nil
        await database.clear()
        print("📊 Local database cleared")
    }

    func onSubscriptionError(client: SpacetimeDBClient, queryId: UInt32, requestId: UInt32?, error: String) async {
        print("❌ Subscription error (queryId: \(queryId), requestId: \(requestId.map(String.init) ?? "nil")): \(error)")
        subscriptionReady = false
        subscription = nil
    }

    // MARK: Table updates

    func onTableUpdate(client: SpacetimeDBClient, event: TableEvent) async {
        print("📊 Table '\(event.tableName)' update: \(event.deletes.count) deletes, \(event.inserts.count) inserts")

        switch event.tableName {
        case "user":
            await applyUserDiff(deletes: event.deletes, inserts: event.inserts)
        case "message":
            await applyMessageDiff(deletes: event.deletes, inserts: event.inserts)
        default:
            print("   ⚠️  Unknown table: \(event.tableName)")
        }

        let userCount = await database.getUserCount()
        let messageCount = await database.getMessageCount()
        print("📊 Database now has \(userCount) users, \(messageCount) messages")
    }

    private func applyUserDiff(deletes: [Any], inserts: [Any]) async {
        var deletedUsers: [UserRow] = []
        var insertedUsers: [UserRow] = []

        for row in deletes {
            guard let user = row as? UserRow else { continue }
            deletedUsers.append(user)
            await database.removeUser(user)
        }
        for row in inserts {
            guard let user = row as? UserRow else { continue }
            insertedUsers.append(user)
            await database.addUser(user)
        }

        // Match by identity to detect renames.
        for deletedUser in deletedUsers {
            if let updated = insertedUsers.first(where: { $0.identity == deletedUser.identity }) {
                let oldName = deletedUser.name ?? "<unnamed>"
                let newName = updated.name ?? "<unnamed>"
                print("   📝 User \(oldName) renamed to \(newName)")
                continue
            }
            let displayName = deletedUser.name ?? "<unnamed>"
            print("   👤 Removed user: \(displayName) \(deletedUser.online ? "🟢" : "⚫")")
        }

        for insertedUser in insertedUsers {
            if deletedUsers.contains(where: { $0.identity == insertedUser.identity }) { continue }
            let displayName = insertedUser.name ?? "<unnamed>"
            print("   👤 Added user: \(displayName) \(insertedUser.online ? "🟢" : "⚫")")
        }
    }

    private func applyMessageDiff(deletes: [Any], inserts: [Any]) async {
        for row in deletes {
            if let msg = row as? MessageRow {
                await database.removeMessage(msg)
                print("   💬 Removed message")
            }
        }
        for row in inserts {
            guard let msg = row as? MessageRow else { continue }
            await database.addMessage(msg)
            let users = await database.getAllUsers()
            let senderName = users.first(where: { $0.identity == msg.sender })?.name ?? "Unknown"
            let date = Date(timeIntervalSince1970: Double(msg.sent) / 1_000_000.0)
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timeString = formatter.string(from: date)
            if msg.sender == myIdentity {
                print("\n➡️  [\(timeString)] You: \(msg.text)")
            } else {
                print("\n💬 [\(timeString)] \(senderName): \(msg.text)")
            }
        }
    }

    // MARK: Reducer responses

    func onReducerResponse(client: SpacetimeDBClient, requestId: UInt32, reducerName: String, outcome: ReducerOutcome) async {
        print("🔔 Reducer response: \(reducerName) (req=\(requestId))")
        switch outcome {
        case .ok(let returnValue, _):
            print("   ✅ committed (\(returnValue.count) bytes returned)")
            if reducerName == "set_name" {
                print("   ✅ Name change was successful!")
            }
        case .okEmpty:
            print("   ✅ committed (empty)")
            if reducerName == "set_name" {
                print("   ✅ Name change was successful!")
            }
        case .error(let bytes):
            print("   ❌ reducer error (\(bytes.count) bytes payload)")
        case .internalError(let message):
            print("   ❌ internal error: \(message)")
        }
    }

    // MARK: Public helpers

    func isSubscriptionReady() -> Bool { subscriptionReady }
    func getAllUsers() async -> [UserRow] { await database.getAllUsers() }
    func getMyIdentity() -> UInt256? { myIdentity }
    func setIntentionalDisconnect() { isIntentionalDisconnect = true }
    func getActiveSubscription() -> UInt32? { subscription?.queryId }

    func subscribe(client: SpacetimeDBClient) async throws -> UInt32 {
        if let existing = subscription { return existing.queryId }
        let handle = try await client.subscribe(["SELECT * FROM user", "SELECT * FROM message"])
        subscription = handle
        print("📡 Subscription request sent (queryId: \(handle.queryId))")
        return handle.queryId
    }

    func unsubscribe() async throws {
        guard let handle = subscription else {
            print("⚠️ No active subscription to unsubscribe from")
            return
        }
        try await handle.unsubscribe()
    }
}
