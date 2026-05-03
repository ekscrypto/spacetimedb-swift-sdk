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


struct ClientConfig {
    let host: String
    let db: String
    let token: AuthenticationToken?

    static func fromEnvironment() -> ClientConfig {
        let env = ProcessInfo.processInfo.environment
        let host = env["SPACETIMEDB_HOST"] ?? "http://localhost:3000"
        let db = env["SPACETIMEDB_DB"] ?? "quickstart-chat"
        let token = env["SPACETIMEDB_TOKEN"].flatMap { value -> AuthenticationToken? in
            value.isEmpty ? nil : AuthenticationToken(rawValue: value)
        }
        return ClientConfig(host: host, db: db, token: token)
    }
}

@main
struct QuickstartChat {
    static func fetchUsersOnly() async {
        print("🔍 Fetching users using OneOffQuery...")

        let config = ClientConfig.fromEnvironment()

        do {
            // Create client for one-off query
            let client = try SpacetimeDBClient(
                host: config.host,
                db: config.db
            )

            // Register row decoders before connecting (BSATNRow path).
            await client.registerTableRowDecoder(UserRow.self)

            // Token precedence: env override > saved > anonymous
            let token = config.token ?? TokenStorage.load()
            if config.token != nil {
                print("🔑 Using token from SPACETIMEDB_TOKEN")
            } else if token != nil {
                print("🔑 Using saved authentication token")
            } else {
                print("ℹ️ No token found - connecting as anonymous user")
            }

            // Connect with delegate that signals when connection is ready
            let delegate = OneOffQueryDelegate()
            try await client.connect(token: token, delegate: delegate)

            // Wait for connection and identity to be fully established
            await delegate.waitForConnection()

            // Execute one-off query to get all users with longer timeout.
            // Rows are returned directly; failures throw OneOffQueryError.
            print("📤 Sending OneOffQuery...")
            let rows: [SingleTableRows]
            do {
                rows = try await client.oneOffQuery("SELECT * FROM user", timeout: 30.0)
            } catch let OneOffQueryError.serverError(message) {
                print("❌ Query error: \(message)")
                exit(1)
            }

            print("✅ Query executed successfully")

            guard rows.contains(where: { $0.tableName == "user" }) else {
                print("📊 No user table found in results")
                await client.disconnect()
                return
            }

            // Decode user rows using the client's registered decoder.
            let users: [UserRow] = await client.decodeRows(from: rows, table: "user")

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
                                _ = try await client.callReducer(reducer)
                                print("   ✅ Name set")
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
                        if let active = delegate.getActiveSubscription() {
                            print("⚠️ Already subscribed (queryId: \(active))")
                        } else {
                            do {
                                let queryId = try await delegate.subscribe(client: client)
                                print("📡 Subscribed (queryId: \(queryId))")
                            } catch {
                                print("❌ Failed to subscribe: \(error)")
                            }
                        }

                    case "/unsub":
                        do {
                            try await delegate.unsubscribe()
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
        // Force line-buffered stdout so output appears promptly when
        // stdout is redirected to a file or pipe (Swift defaults to
        // block-buffering in that case).
        setvbuf(stdout, nil, _IOLBF, 0)
        let config = ClientConfig.fromEnvironment()

        print("Starting SpacetimeDB Client...")
        print("SpacetimeDB Quickstart Chat Client")
        print("==========================================")
        print("Host: \(config.host)")
        print("Database: \(config.db)")
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

        if args.contains("--streams") {
            await runStreamsMode(config: config)
            return
        }

        let noSubscribe = args.contains("--no-subscribe")
        if noSubscribe {
            print("🚫 Auto-subscription disabled - will not subscribe to any tables\n")
        }

        // Token precedence: env override > saved > anonymous (server issues one)
        let token = config.token ?? TokenStorage.load()
        if config.token != nil {
            print("🔑 Using token from SPACETIMEDB_TOKEN")
        } else if token != nil {
            print("🔑 Using saved authentication token")
        } else {
            print("ℹ️ No token found - server will issue a new identity")
        }

        let delegate = ChatClientDelegate(autoSubscribe: !noSubscribe)

        do {
            // Register before connecting
            let client = try SpacetimeDBClient(
                host: config.host,
                db: config.db
            )
            await client.registerTableRowDecoder(UserRow.self)
            await client.registerTableRowDecoder(MessageRow.self)

            print("Attempting to connect...")
            try await client.connect(token: token, delegate: delegate)

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

    /// Streams-only path. Replaces ChatClientDelegate with the
    /// AsyncStream + SubscriptionHandle + Credentials API. Triggered
    /// via `quickstart-chat --streams`.
    static func runStreamsMode(config: ClientConfig) async {
        do {
            print("🚀 Streams mode (no SpacetimeDBClientDelegate)\n")

            // Token precedence: env override > saved credentials file > anonymous.
            // (Streams demo uses the file-backed Credentials path because the
            // Keychain path may prompt for Touch ID / password and block in
            // headless environments. Real apps on macOS/iOS should use the
            // Keychain `Credentials.save()` / `Credentials.load()` overloads.)
            let credsURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("spacetimedb-streams-demo.json")
            let token: AuthenticationToken?
            if let envToken = config.token {
                token = envToken
                print("🔑 Using token from SPACETIMEDB_TOKEN")
            } else if let creds = try? Credentials.load(from: credsURL) {
                token = creds.authenticationToken
                print("🔑 Using saved credentials (identity \(creds.identity.abbreviated)…)")
            } else {
                token = nil
                print("ℹ️ No token found - server will issue a new identity")
            }

            let chat = try StreamsChat(host: config.host, db: config.db, credentialsURL: credsURL)
            try await chat.run(token: token)

            // REPL.
            while true {
                guard let raw = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                    continue
                }
                if raw == "/quit" {
                    print("👋 Goodbye!")
                    await chat.shutdown()
                    return
                }
                if raw.hasPrefix("/name ") {
                    let name = String(raw.dropFirst("/name ".count))
                    do { try await chat.setName(name) }
                    catch { print("❌ \(error)") }
                    continue
                }
                if raw == "/help" {
                    print("\n📖 Streams-mode commands:")
                    print("   /quit          - Exit")
                    print("   /name <name>   - Set your display name")
                    print("   <text>         - Send a chat message\n")
                    continue
                }
                do { try await chat.sendMessage(raw) }
                catch { print("❌ \(error)") }
            }
        } catch {
            print("❌ Fatal Error: \(error)")
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
