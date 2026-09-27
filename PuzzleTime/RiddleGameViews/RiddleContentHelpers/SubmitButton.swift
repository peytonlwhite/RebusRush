//
//  SubmitButton.swift
//  PuzzleTime
//
//  Created by Peyton White on 11/4/25.
//

import SwiftUI

// MARK: - Submit Button
struct SubmitButton: View {
    @Binding var isLoading: Bool
    let userAnswer: String
    let onSubmit: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: onSubmit) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
                Text(isLoading ? "Checking…" : "Submit")
            }
            .font(.title3).bold()
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(submitGradient)
            .foregroundColor(.white)
            .cornerRadius(16)
            .shadow(color: accentColor.opacity(0.5), radius: 8)
        }
        .disabled(isLoading || userAnswer.trimmingCharacters(in: .whitespaces).isEmpty)
        .padding(.horizontal)
    }

    private var submitGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: isLoading ? [.gray] : [Color(hex: "FF6B6B"), Color(hex: "4ECDC4")],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            return LinearGradient(
                colors: isLoading ? [.gray] : [.blue, .purple],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    private var accentColor: Color { colorScheme == .dark ? .pink : .purple }
}



struct SolvedButton: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var animate: Bool = true

    var body: some View {
        Button(action: {}) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                Text("Solved")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(solvedGradient)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    )
            )
            .shadow(color: glowColor.opacity(0.6), radius: 10)
            .opacity(0.8) // Subtle opacity for disabled state
        }
        .disabled(true)
        .padding(.horizontal)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                animate = false
            }
        }
    }

    private var solvedGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(
                colors: [Color(hex: "2ECC71"), Color(hex: "27AE60")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [.green, Color(hex: "2ECC71")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }

    private var glowColor: Color {
        colorScheme == .dark ? .green.opacity(0.8) : .green.opacity(0.6)
    }
}
