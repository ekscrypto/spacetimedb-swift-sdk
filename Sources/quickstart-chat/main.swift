import Foundation
import spacetimedb_swift_sdk
import BSATN

@main
struct QuickstartChat {
    static func main() async {
        print("SpacetimeDB Quickstart Chat Client")
        print("==========================================")
        print("Host: http://localhost:3000")
        print("Database: quickstart-chat")
        print("==========================================\n")
        
        let delegate = ChatClientDelegate()
        
        do {
            let client = try SpacetimeDBClient(
                host: "http://localhost:3000",
                db: "quickstart-chat"
            )
            
            print("Attempting to connect...")
            try await client.connect(delegate: delegate)
            
            print("\n📡 Waiting for server response...")
            print("Press Ctrl+C to exit.\n")
            
            // Setup signal handler for graceful shutdown
            signal(SIGINT) { _ in
                print("\n\n👋 Received shutdown signal...")
                exit(0)
            }
            
            // Keep the program running
            while true {
                try await Task.sleep(nanoseconds: 1_000_000_000) // Sleep for 1 second
                
                if await !client.connected {
                    print("\n⚠️  Connection lost. Exiting...")
                    break
                }
            }

        } catch {
            print("\n❌ Fatal Error: \(error)")
            exit(1)
        }
    }
}

final class ChatClientDelegate: SpacetimeDBClientDelegate, @unchecked Sendable {
    func onConnect() async {
        print("✅ Connected to SpacetimeDB!")
    }
    
    func onError(_ error: any Error) async {
        print("❌ Error: \(error)")
    }
    
    func onDisconnect() async {
        print("🔌 Disconnected from SpacetimeDB")
    }
    
    func onIncomingMessage(_ message: Data) async {
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
}
