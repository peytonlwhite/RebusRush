import Foundation
import Firebase
import Combine
import FirebaseFirestore
import FirebaseAuth

struct Riddle: Identifiable, Codable, Equatable, Hashable {
    @DocumentID var id: String? // Firestore auto-ID or custom
    let photoUrl: String // <-- NEW: remote image
    let answer: String
    let hints: [String]
    let explanation: String
    var difficulty: String? = nil
    var generationWeek: String? = nil
    var createdAt: Date? = nil
    var retired: Bool? = nil

    var difficultyLabel: String? {
        guard let difficulty, ["easy", "medium", "hard"].contains(difficulty.lowercased()) else { return nil }
        return difficulty.capitalized
    }

    func isNew(at now: Date = Date()) -> Bool {
        guard generationWeek != nil, let createdAt else { return false }
        return createdAt <= now && createdAt >= now.addingTimeInterval(-7 * 86400)
    }
    
    // For SwiftUI ForEach
    var uiId: String { id ?? photoUrl }
    
    // Custom equality based on uiId (safe and fast)
    static func == (lhs: Riddle, rhs: Riddle) -> Bool {
        return lhs.uiId == rhs.uiId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uiId)
    }
}
// NEW: Struct for timer challenge progress
struct TimerChallengeProgress: Codable {
    let riddleId: String
    var isCorrect: Bool
    var attempts: Int
    var usedHints: Int
    var lastSeen: Date
    var revealedHintIndices: [Int]
    // For loading from Firestore
    init(riddleId: String, isCorrect: Bool, attempts: Int, usedHints: Int, lastSeen: Date, revealedHintIndices: [Int]) {
        self.riddleId = riddleId
        self.isCorrect = isCorrect
        self.attempts = attempts
        self.usedHints = usedHints
        self.lastSeen = lastSeen
        self.revealedHintIndices = revealedHintIndices
    }
    // For loading from timerDailyChallengeProgress document
    init(riddleIds: [String], played: Bool, completed: Bool, timeRemaining: Int?, timeTakenSeconds: Int, riddleOneCorrect: Bool, riddleTwoCorrect: Bool, riddleThreeCorrect: Bool, hintsUsedRiddleOne: Int, hintsUsedRiddleTwo: Int, hintsUsedRiddleThree: Int, revealedHintIndicesRiddleOne: [Int], revealedHintIndicesRiddleTwo: [Int], revealedHintIndicesRiddleThree: [Int], attemptsRiddleOne: Int, attemptsRiddleTwo: Int, attemptsRiddleThree: Int) {
        self.riddleId = riddleIds.first ?? ""
        self.isCorrect = riddleOneCorrect // Default to first riddle; will be overridden
        self.attempts = attemptsRiddleOne
        self.usedHints = hintsUsedRiddleOne
        self.lastSeen = Date()
        self.revealedHintIndices = revealedHintIndicesRiddleOne
    }
}
struct RiddleProgress: Codable, Identifiable {
    @DocumentID var id: String?
    let riddleId: String
    var isCorrect: Bool = false
    var attempts: Int = 0
    var usedHints: Int = 0
    var lastSeen: Date = Date()
    var solvedDate: Date? // NEW
    var coinsEarned: Int // NEW: Track coins for this riddle
    var revealedHintIndices: [Int] // NEW: Store hint indices (e.g., [0, 1] for first two hints)
    
    // For SwiftUI id
    var uiId: String { id ?? riddleId }
}

@MainActor
final class RiddleViewModel: ObservableObject {
    @Published var riddles: [Riddle] = []
    @Published var weeklyRiddles: [Riddle] = []
    @Published var timerRiddles: [Riddle] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var progressCache: [String: RiddleProgress] = [:] // For regular play
    @Published var dailyProgressCache: [String: RiddleProgress] = [:] // For daily challenges
    @Published var timerProgressCache: [String: TimerChallengeProgress] = [:] // For timer challenges
    private(set) var timerSavedData: [String: Any]?
    @Published var dailyRiddle: Riddle? = nil
    private(set) var dailyChallengeDate = Date()
    var timerChallengeDate = Date()
    @Published var isDailyMode = false
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    @Published var isTimerPaused: Bool = false
    @Published var hasLoadedDailyTen = false
    
    
    init() {
        print("in itnit on riddleviewmodel")
    }
    
    func pauseTimer() {
        isTimerPaused = true
    }
    func resumeTimer() {
        isTimerPaused = false
    }
    
    func loadDailyRiddle() async {
        dailyChallengeDate = Date()
        let docRef = db.collection("dailyChallenges").document(dailyChallengeDate.utcDayString)
        do {
            let doc = try await docRef.getDocument()
            guard doc.exists, let data = doc.data(), let riddleId = data["riddleId"] as? String else {
                await loadFallbackDaily()
                return
            }
            if let riddle = riddles.first(where: { $0.uiId == riddleId }) {
                dailyRiddle = riddle
            } else {
                dailyRiddle = try await db.collection("riddles").document(riddleId)
                    .getDocument(as: Riddle.self)
            }
            if dailyRiddle?.retired == true {
                // Keep a player's existing daily progress attached to its puzzle.
                if let uid = Auth.auth().currentUser?.uid {
                    let progress = try await db.collection("users").document(uid)
                        .collection("dailychallengeprogress").document(dailyChallengeDate.utcDayString).getDocument()
                    if progress.exists { return }
                }
                await loadFallbackDaily()
            }
        } catch {
            print("Daily riddle error: \(error)")
            await loadFallbackDaily()
        }
    }
    
    
    private func loadFallbackDaily() async {
        dailyRiddle = riddles.shuffled().first
    }
    
    /// Read clock, results, and puzzle IDs from one snapshot; errors are not new games.
    func loadTimerChallengeProgress(for userId: String, date: Date) async throws -> [String: Any]? {
        guard !userId.isEmpty, userId != "guest" else {
            throw NSError(domain: "RebusRush", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Sign in before starting a challenge."])
        }
        let snapshot = try await db.collection("users").document(userId)
            .collection("timerDailyChallengeProgress").document(date.utcDayString).getDocument()
        guard snapshot.exists, let data = snapshot.data() else {
            timerProgressCache.removeAll()
            timerRiddles.removeAll()
            timerSavedData = nil
            return nil
        }
        let ids = GameRules.timerSuffixes.compactMap { data["riddleId\($0)"] as? String }
        guard ids.count == 3, Set(ids).count == 3,
              GameRules.timerRemainingSeconds(data) != nil else {
            throw NSError(domain: "RebusRush", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Saved challenge data is incomplete. Please try again."])
        }
        var restored: [Riddle] = []
        for id in ids {
            if let local = (riddles + timerRiddles).first(where: { $0.uiId == id }) {
                restored.append(local)
            } else {
                restored.append(try await db.collection("riddles").document(id).getDocument(as: Riddle.self))
            }
        }
        var progress: [String: TimerChallengeProgress] = [:]
        for (index, riddle) in restored.enumerated() {
            progress[riddle.uiId] = TimerChallengeProgress(
                riddleId: riddle.uiId,
                isCorrect: GameRules.timerValue(data, prefix: "riddle", index: index, ending: "Correct", default: false),
                attempts: GameRules.timerValue(data, prefix: "attemptsRiddle", index: index, default: 0),
                usedHints: GameRules.timerValue(data, prefix: "hintsUsedRiddle", index: index, default: 0),
                lastSeen: Date(),
                revealedHintIndices: GameRules.timerValue(data, prefix: "revealedHintIndicesRiddle", index: index, default: [Int]()))
        }
        timerRiddles = restored
        timerProgressCache = progress
        timerSavedData = data
        return data
    }

    func loadTimerDailyRiddles(date: Date = Date()) async {
        timerRiddles.removeAll()
        let docRef = db.collection("timerRiddlesDaily").document(date.utcDayString)
        do {
            let doc = try await docRef.getDocument()
            guard doc.exists, let data = doc.data(),
                  let id1 = data["riddleId1"] as? String,
                  let id2 = data["riddleId2"] as? String,
                  let id3 = data["riddleId3"] as? String else {
                print("No timer daily riddles found for today – will rely on progress restore")
                return
            }
            
            let ids = [id1, id2, id3]
            var fetched: [Riddle] = []
            
            for rid in ids {
                if let local = riddles.first(where: { $0.uiId == rid }) {
                    fetched.append(local)
                } else {
                    let ref = db.collection("riddles").document(rid)
                    if let remote = try? await ref.getDocument(as: Riddle.self) {
                        fetched.append(remote)
                    }
                }
            }
            
            var active = fetched.filter { $0.retired != true }
            if active.count < 3 {
                let library = await fetchAllRiddles()
                for replacement in library where !active.contains(where: { $0.uiId == replacement.uiId }) {
                    guard active.count < 3 else { break }
                    active.append(replacement)
                }
            }
            if active.count == 3 { timerRiddles = active }
        } catch {
            print("Error loading timer daily riddles: \(error)")
        }
    }
    
    
    private func loadFallbackTimerRiddles() async {
        timerRiddles = Array(riddles.prefix(3)) // CHANGED: No shuffled() for consistency
    }
    func clearProgressCache() {
        progressCache.removeAll()
        timerProgressCache.removeAll()
        timerSavedData = nil
        print("RiddleViewModel: Cleared progress cache")
    }
    
    private func fetchAllRiddles() async -> [Riddle] {
        do {
            let snapshot = try await db.collection("riddles")
                .order(by: "createdAt")
                .getDocuments()
            
            return try snapshot.documents.compactMap { try $0.data(as: Riddle.self) }.filter { $0.retired != true }
        } catch {
            print("Failed to fetch riddles: \(error)")
            errorMessage = "Couldn't load puzzles. Check your connection and try again."
            return []
        }
    }
    
    func loadRiddles() async {
        isLoading = true
        errorMessage = nil
        
        // 1. Always load ALL riddles in background
        let allRiddles = await fetchAllRiddles()
        guard errorMessage == nil else {
            isLoading = false
            return
        }
        weeklyRiddles = allRiddles.filter { $0.isNew() }.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        self.riddles = allRiddles
        
        // 2. If no user → guest mode: just show 5 random riddles
        guard let currentUser = Auth.auth().currentUser else {
            self.riddles = Array(allRiddles.shuffled().prefix(5))
            isLoading = false
            return
        }
        
        let userId = currentUser.uid
        
        // 3. Fetch the admin-configured daily riddle count (default to 5 if missing)
        let adminSettingsRef = db.collection("adminSettings").document("riddleSettings")
        var dailyRiddleCount = 5 // default fallback
        
        do {
            let adminDoc = try await adminSettingsRef.getDocument()
            if adminDoc.exists,
               let data = adminDoc.data(),
               let countFromAdmin = data["newRiddleCount"] as? Int,
               countFromAdmin > 0 {
                dailyRiddleCount = countFromAdmin
                print("📊 Using admin-configured daily riddle count: \(dailyRiddleCount)")
            } else {
                print("📊 No valid newRiddleCount in adminSettings → using default of 5")
            }
        } catch {
            print("⚠️ Failed to fetch admin riddle count: \(error). Using default of 5")
        }
        
        // 4. Try to load today's saved riddles from user's Firestore
        let todayStr = Date.utcDayString
        let dailyRef = db.collection("users").document(userId)
            .collection("dailyTenRiddles").document(todayStr) // keep collection name as-is for backward compatibility
        
        do {
            let doc = try await dailyRef.getDocument()
            
            if doc.exists,
               let data = doc.data(),
               let savedIds = data["riddleIds"] as? [String],
               savedIds.count == dailyRiddleCount {
                
                var savedRiddles: [Riddle] = []
                for id in savedIds {
                    if let active = allRiddles.first(where: { $0.uiId == id }) {
                        savedRiddles.append(active)
                    } else if let saved = try? await db.collection("riddles").document(id).getDocument(as: Riddle.self) {
                        savedRiddles.append(saved)
                    }
                }
                
                if savedRiddles.count == dailyRiddleCount {
                    self.riddles = savedRiddles
                    self.hasLoadedDailyTen = true
                    isLoading = false
                    return
                }
            }
            
            // 5. No valid saved set → generate new random unsolved ones
            await loadProgress(for: userId) // refresh progress cache
            
            let solvedIds = Set(progressCache.filter { $0.value.isCorrect }.keys)
            let newSelection = GameRules.dailySelection(allRiddles.shuffled(), count: dailyRiddleCount) {
                solvedIds.contains($0.uiId)
            }

            let newIds = newSelection.map { $0.uiId }
            
            // Save to user's daily collection for consistency tomorrow
            try await dailyRef.setData([
                "riddleIds": newIds,
                "generatedAt": Timestamp(),
                "count": dailyRiddleCount // optional: store for debugging
            ])
            
            self.riddles = newSelection
            self.hasLoadedDailyTen = true
            
        } catch {
            print("Daily riddles load/save failed: \(error)")
            // Ultimate fallback: random selection using admin count
            self.riddles = GameRules.dailySelection(allRiddles.shuffled(), count: dailyRiddleCount) {
                progressCache[$0.uiId]?.isCorrect == true
            }
            self.hasLoadedDailyTen = true
        }
        
        isLoading = false
    }
    
    
    
    func loadProgress(for userId: String) async {
        guard !userId.isEmpty, userId != "guest" else { return }
        
        let base = db.collection("users").document(userId)
        
        do {
            // Regular progress (all riddles)
            let regularSnap = try await base.collection("riddleProgress").getDocuments()
            var regularCache: [String: RiddleProgress] = [:]
            for doc in regularSnap.documents {
                if let p = try? doc.data(as: RiddleProgress.self) {
                    regularCache[p.riddleId] = p
                }
            }
            progressCache = regularCache
            
            // Daily challenge progress
            dailyProgressCache.removeAll()
            let dailyRef = base.collection("dailychallengeprogress").document(dailyChallengeDate.utcDayString)
            if let dailyRiddle {
                if let doc = try? await dailyRef.getDocument(), doc.exists,
                   let p = try? doc.data(as: RiddleProgress.self), p.riddleId == dailyRiddle.uiId {
                    dailyProgressCache[dailyRiddle.uiId] = p
                }
            }
            
            // Timer challenge progress (today)
            timerProgressCache.removeAll()
            let timerRef = base.collection("timerDailyChallengeProgress").document(Date.utcDayString)
            if let doc = try? await timerRef.getDocument(), doc.exists, let data = doc.data() {
                for (i, riddle) in timerRiddles.enumerated() {
                    let p = TimerChallengeProgress(
                        riddleId: riddle.uiId,
                        isCorrect: GameRules.timerValue(data, prefix: "riddle", index: i, ending: "Correct", default: false),
                        attempts: GameRules.timerValue(data, prefix: "attemptsRiddle", index: i, default: 0),
                        usedHints: GameRules.timerValue(data, prefix: "hintsUsedRiddle", index: i, default: 0),
                        lastSeen: Date(),
                        revealedHintIndices: GameRules.timerValue(data, prefix: "revealedHintIndicesRiddle", index: i, default: [Int]())
                    )
                    timerProgressCache[riddle.uiId] = p
                }
            }
        } catch {
            print("Failed to load progress: \(error)")
        }
    }
    
    func saveProgress(
        riddle: Riddle,
        isCorrect: Bool,
        attempts: Int,
        usedHints: Int,
        userId: String,
        isDaily: Bool,
        date: Date,
        revealedHintIndices: [Int]
    ) async throws -> Int {
        let riddleId = riddle.uiId
        let userRef = db.collection("users").document(userId)
        let progressRef = isDaily
            ? userRef.collection("dailychallengeprogress").document(date.utcDayString)
            : userRef.collection("riddleProgress").document(riddleId)
        let result = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(progressRef)
                let decoded = snapshot.exists ? try snapshot.data(as: RiddleProgress.self) : nil
                let existing = decoded?.riddleId == riddleId ? decoded : nil
                if let existing, existing.isCorrect { return (existing, 0) }
                let hints = GameRules.hintIndices(saved: existing?.revealedHintIndices ?? [],
                                                  visible: revealedHintIndices)
                let hintCount = max(usedHints, hints.count)
                let attemptCount = max(attempts, (existing?.attempts ?? 0) + 1)
                let award = isCorrect ? max(0, 50 - (attemptCount - 1) * 10 - hintCount * 10) : 0
                let progress = RiddleProgress(riddleId: riddleId, isCorrect: isCorrect,
                    attempts: attemptCount, usedHints: hintCount, lastSeen: Date(),
                    solvedDate: isCorrect ? Date() : nil, coinsEarned: award,
                    revealedHintIndices: hints)
                try transaction.setData(from: progress, forDocument: progressRef, merge: true)
                if award > 0 {
                    transaction.setData(["coins": FieldValue.increment(Int64(award))],
                                        forDocument: userRef, merge: true)
                }
                return (progress, award)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        guard let (progress, award) = result as? (RiddleProgress, Int) else {
            throw NSError(domain: "RebusRush", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't save puzzle progress."])
        }
        if isDaily { dailyProgressCache[riddleId] = progress }
        else { progressCache[riddleId] = progress }
        await UserViewModel.shared.refreshCoins()
        if isDaily && progress.isCorrect {
            await UserViewModel.shared.updateStreak(completedToday: true, date: date)
        }
        return award
    }
    
    
    @discardableResult
    func saveTimerChallengeProgress(
        userId: String,
        date: Date = Date(),
        played: Bool,
        completed: Bool,
        timeRemaining: Int?,
        timeTakenSeconds: Int,
        riddleResults: [Int: Bool],
        hintsUsed: [Int: Int],
        revealedHintIndices: [Int: [Int]],
        attempts: [Int: Int],
        rewardForRiddleIndex: Int? = nil
    ) async -> Int? {
        guard !userId.isEmpty, userId != "guest" else { return nil }
        let sessionRiddles = timerRiddles
        guard sessionRiddles.count == 3,
              Set(sessionRiddles.map(\.uiId)).count == 3 else { return nil }
        
        let progressRef = db.collection("users")
            .document(userId)
            .collection("timerDailyChallengeProgress")
            .document(date.utcDayString)
        
        var data: [String: Any] = [
            "played": played,
            "completed": completed,
            "timeRemaining": timeRemaining.map { $0 as Any } ?? NSNull(),
            "timeTakenSeconds": timeTakenSeconds,
            "riddleOneCorrect": riddleResults[0] ?? false,
            "riddleTwoCorrect": riddleResults[1] ?? false,
            "riddleThreeCorrect": riddleResults[2] ?? false,
            "hintsUsedRiddleOne": hintsUsed[0] ?? 0,
            "hintsUsedRiddleTwo": hintsUsed[1] ?? 0,
            "hintsUsedRiddleThree": hintsUsed[2] ?? 0,
            "revealedHintIndicesRiddleOne": revealedHintIndices[0] ?? [],
            "revealedHintIndicesRiddleTwo": revealedHintIndices[1] ?? [],
            "revealedHintIndicesRiddleThree": revealedHintIndices[2] ?? [],
            "attemptsRiddleOne": attempts[0] ?? 0,
            "attemptsRiddleTwo": attempts[1] ?? 0,
            "attemptsRiddleThree": attempts[2] ?? 0
        ]
        
        for (index, suffix) in GameRules.timerSuffixes.enumerated() {
            data["riddleId\(suffix)"] = sessionRiddles[index].uiId
        }

        // Visibility is temporary; purchases must survive auto-hide and autosave.
        for (index, riddle) in sessionRiddles.enumerated() {
            let indices = GameRules.hintIndices(
                saved: timerProgressCache[riddle.uiId]?.revealedHintIndices ?? [],
                visible: revealedHintIndices[index] ?? [])
            let suffix = GameRules.timerSuffixes[index]
            data["revealedHintIndicesRiddle\(suffix)"] = indices
            data["hintsUsedRiddle\(suffix)"] = max(hintsUsed[index] ?? 0, indices.count)
        }
        
        do {
            let proposed = data
            let userRef = db.collection("users").document(userId)
            let result = try await db.runTransaction { transaction, errorPointer -> Any? in
                do {
                    let previous = try transaction.getDocument(progressRef).data() ?? [:]
                    if !previous.isEmpty {
                        guard GameRules.timerSuffixes.allSatisfy({ suffix in
                            previous["riddleId\(suffix)"] as? String == proposed["riddleId\(suffix)"] as? String
                        }), GameRules.timerRemainingSeconds(previous) != nil else {
                            throw NSError(domain: "RebusRush", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Saved challenge differs from this session. Reopen the challenge to restore it."])
                        }
                    }
                    if previous["completed"] as? Bool == true { return (previous, 0) }
                    // An old in-flight save must not reopen an expired run.
                    if previous["played"] as? Bool == true,
                       GameRules.timerRemainingSeconds(previous) == 0 { return (previous, 0) }
                    var next = proposed
                    var award = 0
                    for (index, suffix) in GameRules.timerSuffixes.enumerated() {
                        let hints = GameRules.hintIndices(
                            saved: GameRules.timerValue(previous, prefix: "revealedHintIndicesRiddle", index: index, default: [Int]()),
                            visible: next["revealedHintIndicesRiddle\(suffix)"] as? [Int] ?? [])
                        let hintCount = max(hints.count,
                            max(GameRules.timerValue(previous, prefix: "hintsUsedRiddle", index: index, default: 0),
                                next["hintsUsedRiddle\(suffix)"] as? Int ?? 0))
                        let wasCorrect = GameRules.timerValue(previous, prefix: "riddle", index: index, ending: "Correct", default: false)
                        let isCorrect = next["riddle\(suffix)Correct"] as? Bool == true
                        next["riddle\(suffix)Correct"] = wasCorrect || isCorrect
                        next["revealedHintIndicesRiddle\(suffix)"] = hints
                        next["hintsUsedRiddle\(suffix)"] = hintCount
                        next["attemptsRiddle\(suffix)"] = max(
                            GameRules.timerValue(previous, prefix: "attemptsRiddle", index: index, default: 0),
                            next["attemptsRiddle\(suffix)"] as? Int ?? 0)
                        if rewardForRiddleIndex == index && isCorrect && !wasCorrect {
                            award = max(0, 50 - hintCount * 10)
                        }
                    }
                    let allSolved = GameRules.timerSuffixes.allSatisfy { next["riddle\($0)Correct"] as? Bool == true }
                    next["completed"] = allSolved
                    let remaining = GameRules.remainingAfterSave(previous: previous, proposed: timeRemaining)
                    if allSolved {
                        next["timeRemaining"] = NSNull()
                        next["timeTakenSeconds"] = min(GameRules.timerDuration,
                            max(previous["timeTakenSeconds"] as? Int ?? 0, timeTakenSeconds))
                    } else {
                        next["timeRemaining"] = remaining
                        next["timeTakenSeconds"] = GameRules.timerDuration - remaining
                    }
                    transaction.setData(next, forDocument: progressRef, merge: true)
                    if award > 0 {
                        transaction.setData(["coins": FieldValue.increment(Int64(award))],
                                            forDocument: userRef, merge: true)
                    }
                    return (next, award)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            guard let (committed, award) = result as? ([String: Any], Int) else { return nil }
            // A finished request from an old screen must not replace a newer session's cache.
            guard timerChallengeDate.utcDayString == date.utcDayString,
                  timerRiddles.map(\.uiId) == sessionRiddles.map(\.uiId) else { return award }
            data = committed
            timerSavedData = committed
            // Update cache
            for (i, riddle) in sessionRiddles.enumerated() {
                let p = TimerChallengeProgress(
                    riddleId: riddle.uiId,
                    isCorrect: GameRules.timerValue(data, prefix: "riddle", index: i, ending: "Correct", default: false),
                    attempts: GameRules.timerValue(data, prefix: "attemptsRiddle", index: i, default: 0),
                    usedHints: GameRules.timerValue(data, prefix: "hintsUsedRiddle", index: i, default: 0),
                    lastSeen: Date(),
                    revealedHintIndices: GameRules.timerValue(data, prefix: "revealedHintIndicesRiddle", index: i, default: [Int]())
                )
                timerProgressCache[riddle.uiId] = p
            }
            return award
        } catch {
            print("Save timer progress failed: \(error)")
            return nil
        }
    }
    
    func purchaseHint(
        riddle: Riddle, hintIndex: Int, userId: String,
        isDaily: Bool, isTimerChallenge: Bool, coinsDeducted: Int,
        riddleIndex: Int?, date: Date
    ) async -> Bool {
        guard !userId.isEmpty, userId != "guest", riddle.hints.indices.contains(hintIndex),
              coinsDeducted == 0 || coinsDeducted == 50 else { return false }
        if isTimerChallenge {
            guard let index = riddleIndex, GameRules.timerSuffixes.indices.contains(index) else { return false }
        }
        let riddleId = riddle.uiId
        let userRef = db.collection("users").document(userId)
        let progressRef = isTimerChallenge
            ? userRef.collection("timerDailyChallengeProgress").document(date.utcDayString)
            : isDaily ? userRef.collection("dailychallengeprogress").document(date.utcDayString)
                      : userRef.collection("riddleProgress").document(riddleId)
        do {
            // Paid and ad-earned hints use the same transaction, so neither can undo a solve.
            let result = try await db.runTransaction { transaction, errorPointer -> Any? in
                do {
                    let user = try transaction.getDocument(userRef)
                    let snapshot = try transaction.getDocument(progressRef)
                    let data = snapshot.data() ?? [:]
                    let existing: RiddleProgress?
                    let purchased: [Int]
                    if isTimerChallenge, let index = riddleIndex {
                        guard data["riddleId\(GameRules.timerSuffixes[index])"] as? String == riddleId,
                              data["completed"] as? Bool != true,
                              (GameRules.timerRemainingSeconds(data) ?? 0) > 0 else { return nil }
                        existing = nil
                        purchased = GameRules.timerValue(data, prefix: "revealedHintIndicesRiddle", index: index, default: [Int]())
                    } else {
                        let decoded = snapshot.exists ? try snapshot.data(as: RiddleProgress.self) : nil
                        existing = decoded?.riddleId == riddleId ? decoded : nil
                        purchased = existing?.revealedHintIndices ?? []
                    }
                    let charge = purchased.contains(hintIndex) ? 0 : coinsDeducted
                    let balance = user.data()?["coins"] as? Int ?? 0
                    guard balance >= charge else { return nil }
                    let updated = GameRules.hintIndices(saved: purchased, visible: [hintIndex])
                    if charge > 0 {
                        transaction.updateData(["coins": balance - charge], forDocument: userRef)
                    }
                    if isTimerChallenge, let index = riddleIndex {
                        let suffix = GameRules.timerSuffixes[index]
                        transaction.updateData(["revealedHintIndicesRiddle\(suffix)": updated,
                                                "hintsUsedRiddle\(suffix)": updated.count], forDocument: progressRef)
                        return TimerChallengeProgress(riddleId: riddleId,
                            isCorrect: GameRules.timerValue(data, prefix: "riddle", index: index, ending: "Correct", default: false),
                            attempts: GameRules.timerValue(data, prefix: "attemptsRiddle", index: index, default: 0),
                            usedHints: updated.count, lastSeen: Date(), revealedHintIndices: updated)
                    }
                    let progress = RiddleProgress(riddleId: riddleId,
                        isCorrect: existing?.isCorrect ?? false, attempts: existing?.attempts ?? 0,
                        usedHints: updated.count, lastSeen: Date(), solvedDate: existing?.solvedDate,
                        coinsEarned: existing?.coinsEarned ?? 0, revealedHintIndices: updated)
                    try transaction.setData(from: progress, forDocument: progressRef, merge: true)
                    return progress
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            if let progress = result as? TimerChallengeProgress {
                timerProgressCache[riddleId] = progress
            } else if let progress = result as? RiddleProgress {
                if isDaily { dailyProgressCache[riddleId] = progress }
                else { progressCache[riddleId] = progress }
            } else { return false }
            await UserViewModel.shared.refreshCoins()
            return true
        } catch {
            print("Hint purchase failed: \(error)")
            return false
        }
    }

    func refresh() async {
        await loadRiddles()
        await loadDailyRiddle()
    }
}

// Helper extension for safe indexing
extension Array {
    func safeIndex(_ index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
