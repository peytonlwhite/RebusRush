//
//  RiddleEvaluator.swift
//  PuzzleTime
//
//  Created by Peyton White on 10/30/25.
//

import Foundation
import SwiftUI
import FirebaseAILogic
import FirebaseFirestore   // only if you need Firestore elsewhere

final class RiddleEvaluator {
    // Stable model supported by Firebase AI Logic; reviewed September 2026.
    private static let modelName = "gemini-3.5-flash"
    let ai = FirebaseAI.firebaseAI(backend: .googleAI())
    private let model: GenerativeModel
    
    init() {
        model = ai.generativeModel(modelName: Self.modelName)
        print("RiddleEvaluator: initialized with \(Self.modelName)")
    }
    
    func evaluate(userAnswer: String, riddle: Riddle) async throws -> String {
        let cleaned = GameRules.normalizedAnswer(userAnswer)
        if !cleaned.isEmpty && cleaned == GameRules.normalizedAnswer(riddle.answer) {
            return "correct"
        }

        let prompt = """
        YOU MUST RETURN EXACTLY ONE WORD AND NOTHING ELSE:
        - "correct"
        - "incorrect"

        DO NOT add quotes, punctuation, explanations, or extra text.

        Riddle answer: \(riddle.answer)
        Explanation: \(riddle.explanation)
        Hints: \(riddle.hints.joined(separator: " | "))

        User answer: \(cleaned)

        Compare meaning. Accept spelling/hyphen/space variations.
        """
        
        let response = try await model.generateContent(prompt)
        // Transport failures and malformed responses must not consume an attempt.
        return try GameRules.answerVerdict(response.text)
    }
}
