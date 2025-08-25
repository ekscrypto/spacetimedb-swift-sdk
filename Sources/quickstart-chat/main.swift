import Foundation
import spacetimedb_swift_sdk
import BSATN

extension Data {
    init?(hexString: String) {
        let hex = hexString.replacingOccurrences(of: " ", with: "")
        guard hex.count % 2 == 0 else { return nil }
        
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}

// Token persistence
struct TokenStorage {
    static let tokenFileURL: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("spacetimedb_identity.json")
    }()
    
    struct StoredIdentity: Codable {
        let token: String
        let identity: BSATN.UInt256
        let savedAt: Date
    }
    
    static func save(token: String, identity: BSATN.UInt256) {
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
            print("   Identity: \(stored.identity.description)...")
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
    static func startInputLoop(client: SpacetimeDBClient, delegate: ChatClientDelegate) async {
        var shouldQuit = false
        
        // Wait for subscription to be ready
        while !delegate.isSubscriptionReady() {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        print("\n✅ Subscription ready! You can now use commands.")
        print("💬 Type /help for available commands\n")
        
        while !shouldQuit {
            // Read input from stdin
            if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty {
                // Check if it's a command
                if input.hasPrefix("/") {
                    let components = input.split(separator: " ", maxSplits: 1)
                    let command = String(components[0]).lowercased()
                    let argument = components.count > 1 ? String(components[1]) : nil
                    
                    switch command {
                    case "/quit":
                        print("👋 Goodbye!")
                        shouldQuit = true
                        
                    case "/name":
                        if let name = argument {
                            print("📝 Setting name to: '\(name)'")
                            let reducer = SetNameReducer(userName: name)
                            do {
                                let requestId = try await client.callReducer(reducer)
                                print("   Request sent (ID: \(requestId))")
                            } catch {
                                print("   ❌ Failed to set name: \(error)")
                            }
                        } else {
                            print("⚠️  Usage: /name <your name>")
                        }
                        
                    case "/help":
                        print("\n📖 Available Commands:")
                        print("   /quit - Exit the application")
                        print("   /name <name> - Set your name")
                        print("   /help - Show this help message")
                        print("\nOr just type a message to send to the chat (coming soon!)\n")
                        
                    default:
                        print("❓ Unknown command: \(command)")
                        print("   Type /help for available commands")
                    }
                } else {
                    // Regular message (for future implementation)
                    print("💭 Message sending not yet implemented: \(input)")
                }
            }
            
            // Small delay to prevent CPU spinning
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        // Disconnect before exiting
        await client.disconnect()
    }
    
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

            print("\n📡 Waiting for subscription to be applied...")
            
            // Start input loop (which will wait for subscription internally)
            await startInputLoop(client: client, delegate: delegate)

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
