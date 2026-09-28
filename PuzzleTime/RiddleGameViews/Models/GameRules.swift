import Foundation

/// Shared rules for existing Firestore records and gameplay calculations.
enum GameRules {
    nonisolated static let timerDuration = 180
    nonisolated static let timerSuffixes = ["One", "Two", "Three"]

    nonisolated static func timerValue<T>(_ data: [String: Any], prefix: String, index: Int,
                              ending: String = "", default fallback: T) -> T {
        guard timerSuffixes.indices.contains(index) else { return fallback }
        // Production records use words; accept older numeric keys as a fallback.
        return data["\(prefix)\(timerSuffixes[index])\(ending)"] as? T
            ?? data["\(prefix)\(index + 1)\(ending)"] as? T
            ?? fallback
    }

    nonisolated static func hintIndices(saved: [Int], visible: [Int]) -> [Int] {
        Array(Set(saved).union(visible)).sorted()
    }

    /// A completed run stores elapsed time and a null remaining time.
    nonisolated static func timerRemainingSeconds(_ data: [String: Any]) -> Int? {
        if data["completed"] as? Bool == true {
            guard let elapsed = data["timeTakenSeconds"] as? Int else { return nil }
            return timerDuration - min(timerDuration, max(0, elapsed))
        }
        if let remaining = data["timeRemaining"] as? Int {
            return min(timerDuration, max(0, remaining))
        }
        if data["played"] as? Bool == true, data["timeRemaining"] is NSNull { return 0 }
        return nil
    }

    nonisolated static func remainingAfterSave(previous: [String: Any], proposed: Int?) -> Int {
        let proposed = min(timerDuration, max(0, proposed ?? 0))
        guard let saved = timerRemainingSeconds(previous) else { return proposed }
        return min(saved, proposed)
    }

    nonisolated static func normalizedAnswer(_ answer: String) -> String {
        answer.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func answerVerdict(_ response: String?) throws -> String {
        let verdict = response?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard verdict == "correct" || verdict == "incorrect" else {
            throw NSError(domain: "RebusRush.AnswerEvaluation", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't check your answer. Please try again."])
        }
        return verdict!
    }

    nonisolated static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    nonisolated static func streakAfterSolve(current: Int, lastSolved: Date?, now: Date) -> Int {
        guard let lastSolved else { return 1 }
        let calendar = utcCalendar
        let days = calendar.dateComponents([.day],
            from: calendar.startOfDay(for: lastSolved),
            to: calendar.startOfDay(for: now)).day
        switch days {
        case 0: return max(1, current)
        case 1: return current + 1
        default: return 1
        }
    }
}
