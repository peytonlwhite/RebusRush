//
//  ResultDisplay.swift
//  PuzzleTime
//
//  Created by Peyton White on 11/4/25.
//

import SwiftUI

// MARK: - Result Display
struct ResultDisplay: View {
    let result: String
    let explanation: String
    let currentRiddleId: String        // ← NEW: Pass the riddle's ID
    @Binding var lastAnsweredRiddleId: String  // ← Track which riddle triggered result
    
    @Environment(\.colorScheme) var colorScheme
    
    private var shouldShowResult: Bool {
            !result.isEmpty && lastAnsweredRiddleId == currentRiddleId
        }
    
    var body: some View {
        if shouldShowResult {
            VStack(spacing: 16) {
                Text(result == "error" ? "Couldn't check your answer. Please try again." :
                     (result == "correct" ? "CORRECT!" : "Not Quite"))
                    .font(.title.bold())
                    .foregroundColor(result == "correct" ? successColor : failureColor)
                    .scaleEffect(result == "correct" ? 1.15 : 1.0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: result)
                
                if result == "correct" {
                    Text(explanation)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(resultBackground)
            .cornerRadius(16)
            .shadow(radius: 8)
            .transition(.scale.combined(with: .opacity))
        }
    }
    
    private var successColor: Color { colorScheme == .dark ? .mint : .green }
    private var failureColor: Color { colorScheme == .dark ? .orange : .red }
    private var resultBackground: Color {
        colorScheme == .dark ? Color(hex: "2A2A2A") : Color(.systemGray6)
    }
}
