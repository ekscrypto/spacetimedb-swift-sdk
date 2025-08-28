//
//  ChatClientDelegate.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-25.
//

import Foundation
import SpacetimeDB
import BSATN

final class ChatClientDelegate: SpacetimeDBClientDelegate, @unchecked Sendable {
    private let database = LocalDatabase()
    private var pendingReducer: String? = nil
    private var userNameCache: [UInt256: String?] = [:]  // Track user names for change detection
    private var myIdentity: UInt256? = nil
    private var subscriptionReady: Bool = false
    private var activeSubscription: UInt32? = nil

    func onReconnecting(client: SpacetimeDBClient, attempt: Int) async {
        print("\n🔄 Attempting to reconnect... (attempt \(attempt)/10)")
    }

    func onIdentityReceived(client: SpacetimeDBClient, token: String, identity: UInt256) async {
        print("🆔 Identity received: \(identity.description)...")
        TokenStorage.save(token: token, identity: identity)

        // Store our identity hex for comparison
        myIdentity = identity
    }

    func onSubscribeMultiApplied(client: SpacetimeDBClient, queryId: UInt32) {
        print("✅ Query applied: \(queryId)")
        subscriptionReady = true
        activeSubscription = queryId
        Task {
            let userCount = await database.getUserCount()
            let messageCount = await database.getMessageCount()
            print("📊 Database state: \(userCount) users, \(messageCount) messages")

            // Display recent message history
            let messages = await database.getAllMessages()
            let recentMessages = messages.suffix(10)  // Show last 10 messages

            if !recentMessages.isEmpty {
                print("\n📜 Recent message history:")
                for message in recentMessages {
                    let users = await database.getAllUsers()
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
    }

    func isSubscriptionReady() -> Bool {
        return subscriptionReady
    }

    func getAllUsers() async -> [UserRow] {
        return await database.getAllUsers()
    }

    func getMyIdentity() -> UInt256? {
        return myIdentity
    }

    func onConnect(client: SpacetimeDBClient) async {
        print("\n✅ Connected to SpacetimeDB!")
        subscriptionReady = false  // Reset subscription state on reconnect

        // Clear the local database to avoid duplicates when resubscribing
        await database.clear()

        let queryId = await client.nextQueryId
        _ = try? await client.subscribeMulti(queries: ["SELECT * FROM user", "SELECT * FROM message"], queryId: queryId)
    }

    func onError(client: SpacetimeDBClient, error: any Error) async {
        print("\n❌ Error: \(error)")
    }

    func onDisconnect(client: SpacetimeDBClient) async {
        print("\n⚠️  Connection lost! Will attempt to reconnect automatically...")
        subscriptionReady = false
        activeSubscription = nil
    }

    func onIncomingMessage(client: SpacetimeDBClient, message: Data) async {
        print("📨 Received message (\(message.count) bytes)")

        if message.count > 0 {
            print("   First byte: 0x\(String(format: "%02X", message[0]))")

            if message.count > 16 {
                let preview = message.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
                print("   Preview: \(preview)...")
            } else {
                let hex = message.map { String(format: "%02X", $0) }.joined(separator: " ")
                print("   Data: \(hex)")
            }
        }
    }

    private func onUserTableUdate(deletes: [Any], inserts: [Any]) async {
        // Process deletes and inserts together to detect renames
        var deletedUsers: [UserRow] = []
        var insertedUsers: [UserRow] = []

        // Index deletes by identity
        for row in deletes {
            guard let user = row as? UserRow else { fatalError("Invalid model received for user table") }
            deletedUsers.append(user)
            await database.removeUser(user)
        }

        // Index inserts by identity
        for row in inserts {
            guard let user = row as? UserRow else { fatalError("Invalid model received for user table") }
            insertedUsers.append(user)
            await database.addUser(user)
        }

        // Find renames (same identity in both delete and insert)
    reviewDeletedUsers:
        for deletedUser in deletedUsers {
            for insertedUser in insertedUsers where deletedUser.identity == insertedUser.identity {
                let oldName = deletedUser.name ?? "<unnamed>"
                let newName = insertedUser.name ?? "<unnamed>"
                print("   📝 User \(oldName) renamed to \(newName)")
                continue reviewDeletedUsers
            }
            let displayName = deletedUser.name ?? "<unnamed>"
            let status = deletedUser.online ? "🟢" : "⚫"
            print("   👤 Removed user: \(displayName) \(status)")
        }

        // Report remaining inserts (actual new users)
    reviewInsertedUsers:
        for insertedUser in insertedUsers {
            for deletedUser in deletedUsers where deletedUser.identity == insertedUser.identity {
                continue reviewInsertedUsers
            }
            let displayName = insertedUser.name ?? "<unnamed>"
            let status = insertedUser.online ? "🟢" : "⚫"
            print("   👤 Added user: \(displayName) \(status)")
        }
    }

    private func onMessageTableUpdate(deletes: [Any], inserts: [Any]) async {
        // Process message deletes
        for row in deletes {
            if let message = row as? MessageRow {
                await database.removeMessage(message)
                print("   💬 Removed message")
            }
        }

        // Process message inserts
        for row in inserts {
            if let message = row as? MessageRow {
                await database.addMessage(message)

                // Look up the sender's name
                let users = await database.getAllUsers()
                let senderName = users.first(where: { $0.identity == message.sender })?.name ?? "Unknown"

                // Format the timestamp
                let date = Date(timeIntervalSince1970: Double(message.sent) / 1_000_000.0)
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                let timeString = formatter.string(from: date)

                // Display the message (distinguish our own messages)
                if message.sender == myIdentity {
                    print("\n➡️  [\(timeString)] You: \(message.text)")
                } else {
                    print("\n💬 [\(timeString)] \(senderName): \(message.text)")
                }
            }
        }
    }

    func onTableUpdate(client: SpacetimeDBClient, table: String, deletes: [Any], inserts: [Any]) async {
        print("📊 Table '\(table)' update: \(deletes.count) deletes, \(inserts.count) inserts")

        switch table {
        case "user":
            await onUserTableUdate(deletes: deletes, inserts: inserts)
        case "message":
            await onMessageTableUpdate(deletes: deletes, inserts: inserts)
        default:
            print("   ⚠️  Unknown table: \(table)")
        }

        let userCount = await database.getUserCount()
        let messageCount = await database.getMessageCount()
        print("📊 Database now has \(userCount) users, \(messageCount) messages")
    }

    func onReducerResponse(
        client: SpacetimeDBClient,
        reducer: String,
        requestId: UInt32,
        status: String,
        message: String?,
        energyUsed: UInt128
    ) async {
        print("🔔 Reducer response received:")
        print("   Reducer: \(reducer)")
        print("   Request ID: \(requestId)")
        print("   Status: \(status)")
        print("   Energy used: \(energyUsed)")
        if let message = message {
            print("   Message: \(message)")
        }

        // Special handling for set_name reducer
        if reducer == "set_name" && status == "committed" {
            print("   ✅ Name change was successful!")
        }
    }

    func onUnsubscribeApplied(client: SpacetimeDBClient, queryId: UInt32) async {
        print("✅ Unsubscribe applied: \(queryId)")
        if activeSubscription == queryId {
            activeSubscription = nil
            subscriptionReady = false
            await database.clear()
            print("📊 Local database cleared due to unsubscribe")
        }
    }

    func getActiveSubscription() -> UInt32? {
        return activeSubscription
    }

    func subscribe(client: SpacetimeDBClient) async throws -> UInt32 {
        let queryId = await client.nextQueryId
        _ = try await client.subscribeMulti(queries: ["SELECT * FROM user", "SELECT * FROM message"], queryId: queryId)
        print("📡 Subscription request sent with queryId: \(queryId)")
        return queryId
    }

    func unsubscribe(client: SpacetimeDBClient) async throws {
        guard let queryId = activeSubscription else {
            print("⚠️ No active subscription to unsubscribe from")
            return
        }
        try await client.unsubscribe(queryId: queryId)
        print("📡 Unsubscribe request sent for queryId: \(queryId)")
    }
}
