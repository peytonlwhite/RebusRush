//
//  ConfettiLayer.swift
//  PuzzleTime
//
//  Created by Peyton White on 11/4/25.
//

import SwiftUI
import ConfettiSwiftUI

// MARK: - Confetti Layer
struct ConfettiLayer: View {
    @Binding var trigger: Int
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ConfettiCannon(
            trigger: $trigger,
            num: 60,
            colors: confettiColors,
            confettiSize: 12.0,
            rainHeight: 600.0,
            fadesOut: true,
            openingAngle: .degrees(60),
            closingAngle: .degrees(120),
            radius: 220.0,
            repetitions: 3,
            repetitionInterval: 0.7,
            hapticFeedback: true
        )
    }
    
    private var confettiColors: [Color] {
        colorScheme == .dark
        ? [.cyan, .pink, .mint, .yellow, .orange]
        : [.red, .blue, .green, .yellow, .purple]
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8: (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default: (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
