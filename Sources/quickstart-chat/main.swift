import Foundation
import spacetimedb_swift_sdk
import BSATN

// Token persistence
struct TokenStorage {
    static let tokenFileURL: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("spacetimedb_identity.json")
    }()
    
    struct StoredIdentity: Codable {
        let token: String
        let identity: String
        let savedAt: Date
    }
    
    static func save(token: String, identity: String) {
        let stored = StoredIdentity(token: token, identity: identity, savedAt: Date())
        do {
            let data = try JSONEncoder().encode(stored)
            try data.write(to: tokenFileURL)
            print("💾 Identity saved to: \(tokenFileURL.path)")
        } catch {
            print("⚠️ Failed to save identity: \(error)")
        }
    }
    
    static func load() -> AuthenticationToken? {
        do {
            let data = try Data(contentsOf: tokenFileURL)
            let stored = try JSONDecoder().decode(StoredIdentity.self, from: data)
            print("🔑 Loaded saved identity (saved \(stored.savedAt))")
            print("   Identity: \(String(stored.identity.prefix(16)))...")
            return AuthenticationToken(rawValue: stored.token)
        } catch {
            print("ℹ️ No saved identity found (\(error.localizedDescription))")
            return nil
        }
    }
    
    static func clear() {
        do {
            try FileManager.default.removeItem(at: tokenFileURL)
            print("🗑️ Cleared saved identity")
        } catch {
            print("⚠️ Failed to clear identity: \(error)")
        }
    }
}

@main
struct QuickstartChat {
    static func main() async {
        print("SpacetimeDB Quickstart Chat Client")
        print("==========================================")
        print("Host: http://localhost:3000")
        print("Database: quickstart-chat")
        print("==========================================\n")
        
        // Check for command line arguments
        let args = CommandLine.arguments
        if args.contains("--clear-identity") {
            TokenStorage.clear()
            print("Identity cleared. A new identity will be created.\n")
        }
        
        // Load saved token if available
        let savedToken = TokenStorage.load()
        
        let delegate = ChatClientDelegate()
        
        do {
            // Register before connecting
            let client = try SpacetimeDBClient(
                host: "http://localhost:3000",
                db: "quickstart-chat"
            )
            await client.registerTableRowDecoder(table: "user", decoder: UserRowDecoder())
            await client.registerTableRowDecoder(table: "message", decoder: MessageRowDecoder())
            
            print("Attempting to connect...")
            try await client.connect(token: savedToken, delegate: delegate)

            print("\n📡 Waiting for server response...")
            print("Auto-exit in 5 seconds...\n")
            
            // Auto-exit after 5 seconds
            let startTime = Date()
            while Date().timeIntervalSince(startTime) < 5.0 {
                try await Task.sleep(nanoseconds: 100_000_000) // Sleep for 0.1 seconds
                
                if await !client.connected {
                    print("\n⚠️  Connection lost. Exiting...")
                    break
                }
            }
            
            print("\n⏰ Auto-exit after 5 seconds")

        } catch {
            print("\n❌ Fatal Error: \(error)")
            exit(1)
        }
    }
}

// In-memory database
actor LocalDatabase {
    private var users: [UInt256: UserRow] = [:]
    private var messages: [MessageRow] = []
    
    func addUser(_ user: UserRow) {
        users[user.identity] = user
    }
    
    func removeUser(_ user: UserRow) {
        users[user.identity] = nil
    }
    
    func addMessage(_ message: MessageRow) {
        messages.append(message)
        // Keep messages sorted by timestamp
        messages.sort { $0.sent < $1.sent }
    }
    
    func removeMessage(_ message: MessageRow) {
        messages.removeAll { $0.sender == message.sender && $0.sent == message.sent && $0.text == message.text }
    }
    
    func getUserCount() -> Int {
        return users.count
    }
    
    func getMessageCount() -> Int {
        return messages.count
    }
    
    func getAllUsers() -> [UserRow] {
        return Array(users.values)
    }
    
    func getAllMessages() -> [MessageRow] {
        return messages
    }
}

final class ChatClientDelegate: SpacetimeDBClientDelegate, @unchecked Sendable {
    private let database = LocalDatabase()
    
    func onIdentityReceived(client: SpacetimeDBClient, token: String, identity: String) async {
        print("🆔 Identity received: \(String(identity.prefix(16)))...")
        TokenStorage.save(token: token, identity: identity)
    }
    
    func onSubscribeMultiApplied(client: SpacetimeDBClient, queryId: UInt32) {
        print("✅ Query applied: \(queryId)")
        Task {
            let userCount = await database.getUserCount()
            let messageCount = await database.getMessageCount()
            print("📊 Database state: \(userCount) users, \(messageCount) messages")
        }
    }
    
    func onConnect(client: SpacetimeDBClient) async {
        print("✅ Connected to SpacetimeDB!")
        _ = try? await client.subscribeMulti(queries: ["SELECT * FROM user", "SELECT * FROM message"], queryId: 1)
    }
    
    func onError(client: SpacetimeDBClient, error: any Error) async {
        print("❌ Error: \(error)")
    }
    
    func onDisconnect(client: SpacetimeDBClient) async {
        print("🔌 Disconnected from SpacetimeDB")
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
    
    func onRowsInserted(client: SpacetimeDBClient, table: String, rows: [Any]) async {
        print("➕ Inserting \(rows.count) rows into table '\(table)'")
        
        switch table {
        case "user":
            for row in rows {
                if let user = row as? UserRow {
                    await database.addUser(user)
                    let displayName = user.name ?? "<unnamed>"
                    let status = user.online ? "🟢" : "⚫"
                    print("   👤 Added user: \(displayName) \(status)")
                }
            }
        case "message":
            for row in rows {
                if let message = row as? MessageRow {
                    await database.addMessage(message)
                    print("   💬 Added message: \"\(message.text)\" at \(message.sent)")
                }
            }
        default:
            print("   ⚠️  Unknown table: \(table)")
        }
        
        let userCount = await database.getUserCount()
        let messageCount = await database.getMessageCount()
        print("📊 Database now has \(userCount) users, \(messageCount) messages")
    }
    
    func onRowsDeleted(client: SpacetimeDBClient, table: String, rows: [Any]) async {
        print("➖ Deleting \(rows.count) rows from table '\(table)'")
        
        switch table {
        case "user":
            for row in rows {
                if let user = row as? UserRow {
                    await database.removeUser(user)
                    let displayName = user.name ?? "<unnamed>"
                    let status = user.online ? "🟢" : "⚫"
                    print("   👤 Removed user: \(displayName) \(status)")
                }
            }
        case "message":
            for row in rows {
                if let message = row as? MessageRow {
                    await database.removeMessage(message)
                    print("   💬 Removed message: \"\(message.text)\"")
                }
            }
        default:
            print("   ⚠️  Unknown table: \(table)")
        }
        
        let userCount = await database.getUserCount()
        let messageCount = await database.getMessageCount()
        print("📊 Database now has \(userCount) users, \(messageCount) messages")
    }
}
