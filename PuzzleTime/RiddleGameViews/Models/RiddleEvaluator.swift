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
    let ai = FirebaseAI.firebaseAI(backend: .googleAI())
    private let model: GenerativeModel
    
    init() {
        model = ai.generativeModel(modelName: "gemini-2.5-flash")
        print("RiddleEvaluator: initialized with gemini-2.5-flash")
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
