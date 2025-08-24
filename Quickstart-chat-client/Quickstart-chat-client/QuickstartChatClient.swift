import SwiftUI
import spacetimedb_swift_sdk
import BSATN

@main
struct QuickstartChatClientApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var isConnected = false
    @State private var connectionStatus = "Disconnected"
    @State private var messages: [String] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("SpacetimeDB Quickstart Chat Client")
                .font(.largeTitle)
                .padding()
            
            Text("Status: \(connectionStatus)")
                .foregroundColor(isConnected ? .green : .red)
            
            Button(isConnected ? "Disconnect" : "Connect") {
                Task {
                    if isConnected {
                        // Handle disconnect
                        connectionStatus = "Disconnected"
                        isConnected = false
                    } else {
                        await connectToSpacetimeDB()
                    }
                }
            }
            .padding()
            
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(messages, id: \.self) { message in
                        Text(message)
                            .padding(.horizontal)
                    }
                }
            }
            .border(Color.gray)
            .padding()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private func connectToSpacetimeDB() async {
        let delegate = ChatClientDelegate { [self] message in
            DispatchQueue.main.async {
                self.messages.append(message)
            }
        }
        
        do {
            connectionStatus = "Connecting..."
            
            let client = try SpacetimeDBClient(
                host: "http://localhost:3000",
                db: "quickstart-chat"
            )
            
            try await client.connect(delegate: delegate)
            
            DispatchQueue.main.async {
                self.connectionStatus = "Connected"
                self.isConnected = true
            }
            
        } catch {
            DispatchQueue.main.async {
                self.connectionStatus = "Connection failed: \(error.localizedDescription)"
                self.isConnected = false
            }
        }
    }
}

final class ChatClientDelegate: SpacetimeDBClientDelegate, @unchecked Sendable {
    private let onMessage: (String) -> Void
    
    init(onMessage: @escaping (String) -> Void) {
        self.onMessage = onMessage
    }
    
    func onConnect() async {
        onMessage("✅ Connected to SpacetimeDB!")
    }
    
    func onError(_ error: any Error) async {
        onMessage("❌ Error: \(error)")
    }
    
    func onDisconnect() async {
        onMessage("🔌 Disconnected from SpacetimeDB")
    }
    
    func onIncomingMessage(_ message: Data) async {
        let messageText = "📨 Received message (\(message.count) bytes)"
        onMessage(messageText)
        
        if message.count > 0 {
            let preview = message.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
            onMessage("   Preview: \(preview)...")
        }
    }
}