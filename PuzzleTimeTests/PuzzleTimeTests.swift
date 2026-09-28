//
//  PuzzleTimeTests.swift
//  PuzzleTimeTests
//
//  Created by Peyton White on 10/30/25.
//

import Foundation
import Testing
@testable import PuzzleTime

@MainActor
struct PuzzleTimeTests {

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    @Test func restoresProductionTimerFields() {
        let saved: [String: Any] = [
            "riddleOneCorrect": true, "riddleTwoCorrect": false, "riddleThreeCorrect": true,
            "attemptsRiddleTwo": 4, "hintsUsedRiddleThree": 2,
            "revealedHintIndicesRiddleThree": [0, 2]
        ]
        #expect(GameRules.timerValue(saved, prefix: "riddle", index: 0, ending: "Correct", default: false))
        #expect(!GameRules.timerValue(saved, prefix: "riddle", index: 1, ending: "Correct", default: true))
        #expect(GameRules.timerValue(saved, prefix: "riddle", index: 2, ending: "Correct", default: false))
        #expect(GameRules.timerValue(saved, prefix: "attemptsRiddle", index: 1, default: 0) == 4)
        #expect(GameRules.timerValue(saved, prefix: "hintsUsedRiddle", index: 2, default: 0) == 2)
        #expect(GameRules.timerValue(saved, prefix: "revealedHintIndicesRiddle", index: 2, default: [Int]()) == [0, 2])
    }

    @Test func acceptsLegacyNumericFieldsButPrefersProductionFields() {
        let saved: [String: Any] = ["riddle1Correct": true, "attemptsRiddle2": 3,
                                   "attemptsRiddleTwo": 5]
        #expect(GameRules.timerValue(saved, prefix: "riddle", index: 0, ending: "Correct", default: false))
        #expect(GameRules.timerValue(saved, prefix: "attemptsRiddle", index: 1, default: 0) == 5)
        #expect(GameRules.timerValue(saved, prefix: "attemptsRiddle", index: 3, default: 0) == 0)
    }

    @Test func autoHiddenHintsRemainPurchased() {
        #expect(GameRules.hintIndices(saved: [0, 2], visible: []) == [0, 2])
        #expect(GameRules.hintIndices(saved: [0], visible: [0, 1]) == [0, 1])
    }

    @Test func completedTimerRestoresElapsedTimeForTheMedal() {
        let saved: [String: Any] = ["completed": true, "timeTakenSeconds": 35,
                                   "timeRemaining": NSNull()]
        #expect(GameRules.timerRemainingSeconds(saved) == 145)
    }

    @Test func timeoutIsDifferentFromMissingOrUnreadableProgress() {
        #expect(GameRules.timerRemainingSeconds(["played": true, "timeRemaining": NSNull()]) == 0)
        #expect(GameRules.timerRemainingSeconds([:]) == nil)
        #expect(GameRules.timerRemainingSeconds(["timeRemaining": "bad data"]) == nil)
    }

    @Test func lateSaveCannotRestoreTimeOrReviveAnExpiredRun() {
        #expect(GameRules.remainingAfterSave(previous: ["timeRemaining": 75], proposed: 120) == 75)
        #expect(GameRules.remainingAfterSave(previous: ["played": true, "timeRemaining": NSNull()], proposed: 120) == 0)
        #expect(GameRules.remainingAfterSave(previous: ["timeRemaining": 75], proposed: 60) == 60)
    }

    @Test func timerValuesAreClampedToTheChallengeDuration() {
        #expect(GameRules.timerRemainingSeconds(["timeRemaining": -8]) == 0)
        #expect(GameRules.timerRemainingSeconds(["timeRemaining": 999]) == 180)
        #expect(GameRules.timerRemainingSeconds(["completed": true, "timeTakenSeconds": -3]) == 180)
    }

    @Test func answerNormalizationAcceptsCaseSpacingAndHyphens() {
        #expect(GameRules.normalizedAnswer("  TOP-\nSecret  ") == "top secret")
        #expect(GameRules.normalizedAnswer("therapist") != GameRules.normalizedAnswer("the rapist"))
    }

    @Test func validAIVerdictsAreRecognized() throws {
        #expect(try GameRules.answerVerdict(" CORRECT\n") == "correct")
        #expect(try GameRules.answerVerdict("incorrect") == "incorrect")
    }

    @Test func malformedAIResponsesAreErrorsNotWrongAnswers() {
        for response in [nil, "", "probably correct", "service unavailable"] as [String?] {
            do {
                _ = try GameRules.answerVerdict(response)
                Issue.record("Malformed response should not consume an attempt")
            } catch { /* Expected: the caller shows retry without saving an attempt. */ }
        }
    }

    @Test func repeatSolveDoesNotIncreaseStreak() {
        #expect(GameRules.streakAfterSolve(current: 7,
            lastSolved: date("2026-09-27T00:01:00Z"), now: date("2026-09-27T23:59:00Z")) == 7)
    }

    @Test func consecutiveUTCDaysIncreaseStreakEvenWithinSameLocalDay() {
        #expect(GameRules.streakAfterSolve(current: 7,
            lastSolved: date("2026-09-27T23:59:00Z"), now: date("2026-09-28T00:01:00Z")) == 8)
    }

    @Test func missedDayRestartsStreak() {
        #expect(GameRules.streakAfterSolve(current: 7,
            lastSolved: date("2026-09-25T23:59:00Z"), now: date("2026-09-27T00:01:00Z")) == 1)
    }

    @Test func firstWinWorksForNewAndLegacyUserRecords() {
        let now = date("2026-09-27T12:00:00Z")
        #expect(GameRules.streakAfterSolve(current: 0, lastSolved: nil, now: now) == 1)
        #expect(GameRules.streakAfterSolve(current: 0, lastSolved: now, now: now) == 1)
    }

    @Test func riddleIdentityIsStableWithoutADocumentID() {
        let riddle = Riddle(photoUrl: "https://example.com/riddle.png", answer: "top secret",
                            hints: [], explanation: "Secret is at the top.")
        #expect(riddle.uiId == riddle.uiId)
        #expect(riddle == riddle)
        #expect(Set([riddle, riddle]).count == 1)
    }

    @Test func equalRiddlesHaveMatchingHashesAfterContentChanges() {
        let old = Riddle(id: "top-secret", photoUrl: "https://example.com/old.png",
                         answer: "top secret", hints: [], explanation: "Old")
        let updated = Riddle(id: "top-secret", photoUrl: "https://example.com/new.png",
                             answer: "top secret", hints: ["Look up"], explanation: "Updated")
        #expect(old == updated)
        #expect(Set([old, updated]).count == 1)
    }
}
