//
//  ContentView.swift
//  photo-deleter
//
//  Created by Tom Planche on 22/01/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Photo Deleter")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
