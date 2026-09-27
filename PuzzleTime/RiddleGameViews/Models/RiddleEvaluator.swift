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
        let cleaned = userAnswer
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        print("=== EVALUATION START ===")
        print("User answer (cleaned): '\(cleaned)'")
        
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
        
        print("Prompt sent to Gemini:\n\(prompt)\n")
        
        // CORRECT TYPE: GenerateContentResponse
        let response: GenerateContentResponse
        do {
            response = try await model.generateContent(prompt)
            print("Gemini call succeeded")
        } catch {
            print("Gemini generateContent FAILED: \(error)")
            throw error
        }
        
        // Extract text safely
        guard let rawText = response.text else {
            print("Gemini returned NO text → treating as incorrect")
            return "incorrect"
        }
        
        let trimmed = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        print("Raw Gemini response: \"\(rawText)\"")
        print("Trimmed response: \"\(trimmed)\"")
        
        if trimmed == "correct" {
            print("VERDICT: correct")
            return "correct"
        } else if trimmed == "incorrect" {
            print("VERDICT: incorrect")
            return "incorrect"
        } else {
            print("UNEXPECTED RESPONSE → treating as incorrect: \"\(trimmed)\"")
            return "incorrect"
        }
    }
}

