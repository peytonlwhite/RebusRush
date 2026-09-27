//
//  ContentView.swift
//  PuzzleTime
//
//  Created by Peyton White on 10/30/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var path = NavigationPath()  // NEW: controls navigation

    var body: some View {
        NavigationStack(path: $path) {  // Bind path
                    IntroView(path: $path)     // Pass binding
                }
    }
    
    
}
