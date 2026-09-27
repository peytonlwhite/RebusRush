//
//  AnswerInput.swift
//  PuzzleTime
//
//  Created by Peyton White on 11/4/25.
//

import SwiftUI

// MARK: - Answer Input
struct AnswerInput: View {
    @Binding var userAnswer: String
    @Binding var result: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        TextField("Your answer…", text: $userAnswer)
            .textFieldStyle(.plain)
            .padding(16)
            .background(
                Capsule()
                    .fill(inputBackground)
                    .overlay(Capsule().stroke(accentColor, lineWidth: 2))
                    .shadow(color: accentColor.opacity(0.4), radius: 6)
            )
            .padding(.horizontal)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .foregroundColor(.primary)
            .onChange(of: userAnswer) { _, _ in result = "" }
    }

    private var inputBackground: Color {
        colorScheme == .dark ? Color(hex: "1E1E1E") : Color(.systemBackground)
    }
    private var accentColor: Color { colorScheme == .dark ? .pink : .purple }
}
