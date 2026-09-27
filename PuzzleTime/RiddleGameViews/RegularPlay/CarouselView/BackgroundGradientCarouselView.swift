//
//  BackgroundGradientCarouselView.swift
//  PuzzleTime
//
//  Created by Peyton White on 12/27/25.
//

import SwiftUI

// MARK: - Background Gradient
struct BackgroundGradientCarouselView: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
            ? [Color(hex: "1A1A2E"), Color(hex: "16213E")]
            : [Color(.systemTeal).opacity(0.2), Color(.systemPurple).opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}


// MARK: - DARK MODE WRAPPER
struct DarkModeWrapper<Content: View>: View {
    let content: () -> Content
    
    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        content()
            .preferredColorScheme(.dark)
            .environment(\.colorScheme, .dark)
    }
}



