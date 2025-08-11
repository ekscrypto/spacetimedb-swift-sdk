//
//  ContentView.swift
//  Quickstart-chat-client
//
//  Created by Dave Poirier on 2025-08-09.
//

import SwiftUI

struct ContentView: View {
    @State var chatClient = try! QuickstartChat()

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
        .onAppear() {
            Task { try await chatClient.connect() }
        }
    }
}

#Preview {
    ContentView()
}
