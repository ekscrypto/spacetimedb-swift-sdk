import Foundation
import SpacetimeDB
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

// Delegate for one-off queries  
actor OneOffQueryDelegate: SpacetimeDBClientDelegate {
    private var connectionContinuation: CheckedContinuation<Void, Never>?
    private var identityReceived = false
    private var connected = false
    
    func waitForConnection() async {
        await withCheckedContinuation { continuation in
            self.connectionContinuation = continuation
        }
    }
    
    private func checkReadyAndResume() {
        if connected && identityReceived, let continuation = connectionContinuation {
            print("✅ Connection and identity ready for OneOffQuery")
            continuation.resume()
            connectionContinuation = nil
        }
    }
    
    func onConnect(client: SpacetimeDBClient) async {
        print("🔗 Connection established")
        connected = true
        checkReadyAndResume()
    }
    
    nonisolated func onDisconnect(client: SpacetimeDBClient) async {}
    func onIdentityReceived(client: SpacetimeDBClient, token: String, identity: UInt256) async {
        print("🆔 Identity received: \(identity.description.prefix(8))...")
        identityReceived = true
        checkReadyAndResume()
    }
    nonisolated func onSubscribeMultiApplied(client: SpacetimeDBClient, queryId: UInt32) {}
    nonisolated func onTableUpdate(client: SpacetimeDBClient, table: String, deletes: [Any], inserts: [Any]) async {}
    nonisolated func onReducerResponse(client: SpacetimeDBClient, reducer: String, requestId: UInt32, status: String, message: String?, energyUsed: UInt128) async {}
    nonisolated func onError(client: SpacetimeDBClient, error: Error) async {}
    nonisolated func onReconnecting(client: SpacetimeDBClient, attempt: Int) async {}
    nonisolated func onIncomingMessage(client: SpacetimeDBClient, message: Data) async {}
}

@main
struct QuickstartChat {
    static func fetchUsersOnly() async {
        print("🔍 Fetching users using OneOffQuery...")
        
        do {
            // Create client for one-off query
            let client = try SpacetimeDBClient(
                host: "http://localhost:3000",
                db: "quickstart-chat"
            )
            
            // Register the UserRowDecoder before connecting
            await client.registerTableRowDecoder(table: "user", decoder: UserRowDecoder())
            
            // Load saved token if available (reuse authentication from regular client)
            let savedToken = TokenStorage.load()
            if savedToken != nil {
                print("🔑 Using saved authentication token")
            } else {
                print("ℹ️ No saved token found - connecting as anonymous user")
            }
            
            // Connect with delegate that signals when connection is ready
            let delegate = OneOffQueryDelegate()
            try await client.connect(token: savedToken, delegate: delegate)
            
            // Wait for connection and identity to be fully established
            await delegate.waitForConnection()
            
            // Execute one-off query to get all users with longer timeout  
            print("📤 Sending OneOffQuery...")
            let result = try await client.oneOffQuery("SELECT * FROM user", timeout: 30.0)
            
            if let error = result.error {
                print("❌ Query error: \(error)")
                exit(1)
            }
            
            print("✅ Query executed successfully in \(result.executionDuration) microseconds")
            
            // Check if user table exists in results
            guard result.tables.contains(where: { $0.name == "user" }) else {
                print("📊 No user table found in results")
                await client.disconnect()
                return
            }
            
            // Decode user rows using the client's registered decoder (same as normal table updates)
            let users: [UserRow] = await result.decodeRows(from: "user", using: client)
            
            if users.isEmpty {
                print("📊 No users found in database")
            } else {
                print("\n👥 Users found (\(users.count)):")
                
                for user in users {
                    let displayName = user.name ?? "<unnamed>"
                    let onlineStatus = user.online ? "online" : "offline"
                    let fullIdentity = user.identity.description
                    
                    print("\(fullIdentity) \(displayName) \(onlineStatus)")
                }
            }
            
            await client.disconnect()
            
        } catch {
            print("❌ Failed to fetch users: \(error)")
            exit(1)
        }
    }

    static func showOnlineUsers(delegate: ChatClientDelegate) async {
        let users = await delegate.getAllUsers()
        let onlineUsers = users.filter { $0.online }

        if onlineUsers.isEmpty {
            print("📊 No users currently online")
        } else {
            print("\n👥 Online Users (\(onlineUsers.count)):")
            for user in onlineUsers.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
                let name = user.name ?? "<unnamed>"
                let identityPreview = String(user.identity.description.prefix(8))
                print("   🟢 \(name) (\(identityPreview)...)")
            }
            print("")
        }
    }

    static func startInputLoop(client: SpacetimeDBClient, delegate: ChatClientDelegate, waitForSubscription: Bool = true) async {
        var shouldQuit = false

        if waitForSubscription {
            // Wait for subscription to be ready
            while !delegate.isSubscriptionReady() {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            print("\n✅ Subscription ready! You can now use commands.")
            print("💬 Type /help for available commands\n")
        } else {
            print("\n✅ Connected without subscriptions! You can use commands.")
            print("💬 Type /help for available commands (note: no table data will be received)\n")
        }

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
                        delegate.setIntentionalDisconnect()
                        shouldQuit = true

                    case "/name":
                        if let name = argument, !name.isEmpty {
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
                            print("   Name cannot be empty")
                        }

                    case "/users":
                        await showOnlineUsers(delegate: delegate)

                    case "/sub":
                        if delegate.getActiveSubscription() != nil {
                            print("⚠️ Already subscribed to queryId: \(delegate.getActiveSubscription()!)")
                        } else {
                            do {
                                let queryId = try await delegate.subscribe(client: client)
                                print("📡 Subscribing with queryId: \(queryId)")
                            } catch {
                                print("❌ Failed to subscribe: \(error)")
                            }
                        }

                    case "/unsub":
                        do {
                            try await delegate.unsubscribe(client: client)
                        } catch {
                            print("❌ Failed to unsubscribe: \(error)")
                        }

                    case "/help":
                        print("\n📖 Available Commands:")
                        print("   /quit - Exit the application")
                        print("   /name <name> - Set your name")
                        print("   /users - Show online users")
                        print("   /sub - Subscribe to chat data")
                        print("   /unsub - Unsubscribe from chat data")
                        print("   /help - Show this help message")
                        print("\nOr just type any text to send a message to the chat!\n")

                    default:
                        print("❓ Unknown command: \(command)")
                        print("   Type /help for available commands")
                    }
                } else {
                    // Send as a regular message
                    if !input.isEmpty {
                        let reducer = SendMessageReducer(text: input)
                        do {
                            _ = try await client.callReducer(reducer)
                            // Message will be displayed when we receive it back
                        } catch {
                            print("❌ Failed to send message: \(error)")
                        }
                    }
                }
            }

            // Small delay to prevent CPU spinning
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Disconnect before exiting
        await client.disconnect()
    }

    static func main() async {
        print("Starting SpacetimeDB Client...")
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

        if args.contains("--fetch-users-only") {
            await fetchUsersOnly()
            return
        }

        let useSingleSubs = args.contains("--single")
        if useSingleSubs {
            print("🔀 Using single subscriptions instead of multi-subscriptions\n")
        }

        let noSubscribe = args.contains("--no-subscribe")
        if noSubscribe {
            print("🚫 Auto-subscription disabled - will not subscribe to any tables\n")
        }

        // Load saved token if available
        let savedToken = TokenStorage.load()

        let delegate = ChatClientDelegate(useSingleSubscriptions: useSingleSubs, autoSubscribe: !noSubscribe)

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

            if !noSubscribe {
                print("\n📡 Waiting for subscription to be applied...")
            }

            // Start input loop (which will wait for subscription internally unless disabled)
            await startInputLoop(client: client, delegate: delegate, waitForSubscription: !noSubscribe)

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

    func clear() {
        users.removeAll()
        messages.removeAll()
    }
}
