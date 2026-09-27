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
    
    // For SwiftUI ForEach
    var uiId: String { id ?? UUID().uuidString }
    
    // Custom equality based on uiId (safe and fast)
    static func == (lhs: Riddle, rhs: Riddle) -> Bool {
        return lhs.uiId == rhs.uiId
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
    @Published var timerRiddles: [Riddle] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var progressCache: [String: RiddleProgress] = [:] // For regular play
    @Published var dailyProgressCache: [String: RiddleProgress] = [:] // For daily challenges
    @Published var timerProgressCache: [String: TimerChallengeProgress] = [:] // For timer challenges
    @Published var dailyRiddle: Riddle? = nil
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
        let docRef = db.collection("dailyChallenges").document(Date.utcDayString)
        do {
            let doc = try await docRef.getDocument()
            guard doc.exists, let data = doc.data(), let riddleId = data["riddleId"] as? String else {
                await loadFallbackDaily()
                return
            }
            if let riddle = riddles.first(where: { $0.uiId == riddleId }) {
                dailyRiddle = riddle
            } else {
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
    
    func loadTimerChallengeProgress(for userId: String, date: Date = Date()) async {
        guard !userId.isEmpty, userId != "guest" else { return }
        
        let progressRef = db.collection("users")
            .document(userId)
            .collection("timerDailyChallengeProgress")
            .document(date.utcDayString)
        
        do {
            let doc = try await progressRef.getDocument()
            guard doc.exists, let data = doc.data() else { return }
            
            // Restore timerRiddles from saved IDs if needed
            if timerRiddles.isEmpty {
                if let id1 = data["riddleIdOne"] as? String,
                   let id2 = data["riddleIdTwo"] as? String,
                   let id3 = data["riddleIdThree"] as? String {
                    let ids = [id1, id2, id3]
                    var restored: [Riddle] = []
                    for rid in ids {
                        if let r = riddles.first(where: { $0.uiId == rid }) {
                            restored.append(r)
                        } else {
                            let ref = db.collection("riddles").document(rid)
                            if let r = try? await ref.getDocument(as: Riddle.self) {
                                restored.append(r)
                            }
                        }
                    }
                    if restored.count == 3 { timerRiddles = restored }
                }
            }
            
            timerProgressCache.removeAll()
            for (i, riddle) in timerRiddles.enumerated() {
                let idx = i + 1
                let progress = TimerChallengeProgress(
                    riddleId: riddle.uiId,
                    isCorrect: data["riddle\(idx)Correct"] as? Bool ?? false,
                    attempts: data["attemptsRiddle\(idx)"] as? Int ?? 0,
                    usedHints: data["hintsUsedRiddle\(idx)"] as? Int ?? 0,
                    lastSeen: Date(),
                    revealedHintIndices: data["revealedHintIndicesRiddle\(idx)"] as? [Int] ?? []
                )
                timerProgressCache[riddle.uiId] = progress
            }
        } catch {
            print("Failed to load timer progress: \(error)")
        }
    }
    
    func getRiddleStr(index:Int) -> String {
        if(index == 1) {
            return "One"
        }
        if(index == 2) {
            return "Two"
        }
        if(index == 3) {
            return "Three"
        }
        return "NA"
    }
    
    func loadTimerDailyRiddles(date: Date = Date()) async {
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
            
            if fetched.count == 3 {
                timerRiddles = fetched
            }
        } catch {
            print("Error loading timer daily riddles: \(error)")
        }
    }
    
    
    private func loadFallbackTimerRiddles() async {
        timerRiddles = Array(riddles.prefix(3)) // CHANGED: No shuffled() for consistency
    }
    func clearProgressCache() {
        progressCache.removeAll()
        print("RiddleViewModel: Cleared progress cache")
    }
    
    private func fetchAllRiddles() async -> [Riddle] {
        do {
            let snapshot = try await db.collection("riddles")
                .order(by: "createdAt")
                .getDocuments()
            
            return try snapshot.documents.compactMap { try $0.data(as: Riddle.self) }
        } catch {
            print("Failed to fetch riddles: \(error)")
            return []
        }
    }
    
    func loadRiddles() async {
        isLoading = true
        errorMessage = nil
        
        // 1. Always load ALL riddles in background
        let allRiddles = await fetchAllRiddles()
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
                
                let savedRiddles = savedIds.compactMap { id in
                    allRiddles.first { $0.uiId == id }
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
            let unsolvedRiddles = allRiddles.filter { !solvedIds.contains($0.uiId) }
            
            let newSelection: [Riddle]
            if unsolvedRiddles.count >= dailyRiddleCount {
                newSelection = Array(unsolvedRiddles.shuffled().prefix(dailyRiddleCount))
            } else {
                // Not enough unsolved → fill with random (possibly already solved)
                newSelection = Array(allRiddles.shuffled().prefix(dailyRiddleCount))
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
            self.riddles = Array(allRiddles.shuffled().prefix(dailyRiddleCount))
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
            let dailyRef = base.collection("dailychallengeprogress").document(Date.utcDayString)
            if let dailyRiddle {
                if let doc = try? await dailyRef.getDocument(), doc.exists,
                   let p = try? doc.data(as: RiddleProgress.self) {
                    dailyProgressCache[dailyRiddle.uiId] = p
                }
            }
            
            // Timer challenge progress (today)
            let timerRef = base.collection("timerDailyChallengeProgress").document(Date.utcDayString)
            if let doc = try? await timerRef.getDocument(), doc.exists, let data = doc.data() {
                for (i, riddle) in timerRiddles.enumerated() {
                    let idx = i + 1
                    let p = TimerChallengeProgress(
                        riddleId: riddle.uiId,
                        isCorrect: data["riddle\(idx)Correct"] as? Bool ?? false,
                        attempts: data["attemptsRiddle\(idx)"] as? Int ?? 0,
                        usedHints: data["hintsUsedRiddle\(idx)"] as? Int ?? 0,
                        lastSeen: Date(),
                        revealedHintIndices: data["revealedHintIndicesRiddle\(idx)"] as? [Int] ?? []
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
        coinsEarned: Int,
        userId: String,
        isDaily: Bool,
        revealedHintIndices: [Int]
    ) async {
        let riddleId = riddle.uiId
        let userRef = db.collection("users").document(userId)
        
        let progress = RiddleProgress(
            riddleId: riddleId,
            isCorrect: isCorrect,
            attempts: attempts,
            usedHints: usedHints,
            lastSeen: Date(),
            solvedDate: isCorrect ? Date() : nil,
            coinsEarned: coinsEarned,
            revealedHintIndices: revealedHintIndices
        )
        
        do {
            if isDaily {
                try await userRef.collection("dailychallengeprogress")
                    .document(Date.utcDayString)
                    .setData(from: progress, merge: true)
                dailyProgressCache[riddleId] = progress
            } else {
                try await userRef.collection("riddleProgress")
                    .document(riddleId)
                    .setData(from: progress, merge: true)
                progressCache[riddleId] = progress
            }
            
            if coinsEarned > 0 {
                try await userRef.setData(["coins": FieldValue.increment(Int64(coinsEarned))],merge: true)
                await UserViewModel.shared.refreshCoins()
            }
            
            if isDaily && isCorrect {
                await UserViewModel.shared.updateStreak(completedToday: true)
            }
        } catch {
            print("Save progress failed: \(error)")
        }
    }
    
    
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
        attempts: [Int: Int]
    ) async {
        guard !userId.isEmpty, userId != "guest" else { return }
        
        let progressRef = db.collection("users")
            .document(userId)
            .collection("timerDailyChallengeProgress")
            .document(date.utcDayString)
        
        var data: [String: Any] = [
            "played": played,
            "completed": completed,
            "timeRemaining": timeRemaining as Any,
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
        
        if timerRiddles.count > 0 { data["riddleIdOne"] = timerRiddles[0].uiId }
        if timerRiddles.count > 1 { data["riddleIdTwo"] = timerRiddles[1].uiId }
        if timerRiddles.count > 2 { data["riddleIdThree"] = timerRiddles[2].uiId }
        
        do {
            try await progressRef.setData(data, merge: false)
            // Update cache
            for (i, riddle) in timerRiddles.enumerated() {
                let p = TimerChallengeProgress(
                    riddleId: riddle.uiId,
                    isCorrect: riddleResults[i] ?? false,
                    attempts: attempts[i] ?? 0,
                    usedHints: hintsUsed[i] ?? 0,
                    lastSeen: Date(),
                    revealedHintIndices: revealedHintIndices[i] ?? []
                )
                timerProgressCache[riddle.uiId] = p
            }
        } catch {
            print("Save timer progress failed: \(error)")
        }
    }
    
    func purchaseHint(
        riddle: Riddle,
        hintIndex: Int,
        userId: String,
        isDaily: Bool,
        isTimerChallenge: Bool,
        coinsDeducted: Int,
        currentHintIndices: [Int],
        riddleIndex: Int?
    ) async -> Bool {
        let riddleId = riddle.id ?? riddle.uiId
        let todayStr = Date.utcDayString  // ← Clean & safe
        let userRef = db.collection("users").document(userId)
        
        do {
            // MARK: - 1. PAID HINTS (transaction)
            if coinsDeducted > 0 {
                let result = try await db.runTransaction { transaction, errorPointer -> Any? in
                    do {
                        // 1. READ USER DOCUMENT (must be BEFORE any writes)
                        let userDoc = try transaction.getDocument(userRef)
                        guard let data = userDoc.data(),
                              let currentCoins = data["coins"] as? Int else {
                            return false
                        }
                        
                        guard currentCoins >= coinsDeducted else {
                            return false
                        }
                        
                        // 2. DETERMINE PROGRESS REFERENCE + READ PROGRESS (must be BEFORE any writes)
                        var progressRef: DocumentReference!
                        var existingProgress: RiddleProgress?
                        var existingTimerArray: [Int] = []
                        var field = ""
                        var hintsField = ""
                        
                        if isTimerChallenge,
                           let idx = riddleIndex,
                           idx >= 0, idx < 3 {
                            progressRef = userRef
                                .collection("timerDailyChallengeProgress")
                                .document(todayStr)
                            
                            field = "revealedHintIndicesRiddle\(self.getRiddleStr(index: idx + 1))"
                            hintsField = "hintsUsedRiddle\(self.getRiddleStr(index: idx + 1))"
                            
                            let progressDoc = try transaction.getDocument(progressRef)
                            existingTimerArray = progressDoc.data()?[field] as? [Int] ?? []
                        }
                        else if isDaily {
                            progressRef = userRef
                                .collection("dailychallengeprogress")
                                .document(todayStr)
                            
                            let progressDoc = try transaction.getDocument(progressRef)
                            existingProgress = try? progressDoc.data(as: RiddleProgress.self)
                        } else {
                            progressRef = userRef
                                .collection("riddleProgress")
                                .document(riddleId)
                            
                            let progressDoc = try transaction.getDocument(progressRef)
                            existingProgress = try? progressDoc.data(as: RiddleProgress.self)
                        }
                        
                        // 3. CALCULATE UPDATED HINTS (still no writes yet!)
                        let updatedHints: [Int]
                        
                        if isTimerChallenge {
                            updatedHints = self.buildUpdatedHintIndices(current: existingTimerArray,
                                                                        newHint: hintIndex)
                        } else {
                            updatedHints = self.buildUpdatedHintIndices(
                                current: existingProgress?.revealedHintIndices ?? [],
                                newHint: hintIndex
                            )
                        }
                        
                        // 4. WRITE EVERYTHING (all writes AFTER all reads)
                        transaction.updateData(["coins": currentCoins - coinsDeducted], forDocument: userRef)
                        
                        if isTimerChallenge {
                            transaction.updateData([
                                field: updatedHints,
                                hintsField: updatedHints.count
                            ], forDocument: progressRef)
                            
                            // Update cache (synchronously, no UI impact yet)
                            let cache = self.timerProgressCache[riddleId] ?? TimerChallengeProgress(
                                riddleId: riddleId, isCorrect: false, attempts: 0,
                                usedHints: 0, lastSeen: Date(), revealedHintIndices: []
                            )
                            self.timerProgressCache[riddleId] = TimerChallengeProgress(
                                riddleId: riddleId,
                                isCorrect: cache.isCorrect,
                                attempts: cache.attempts,
                                usedHints: updatedHints.count,
                                lastSeen: Date(),
                                revealedHintIndices: updatedHints
                            )
                        } else {
                            let newProgress = self.buildRiddleProgress(
                                existing: existingProgress,
                                riddleId: riddleId,
                                updatedHints: updatedHints
                            )
                            
                            try transaction.setData(from: newProgress,
                                                    forDocument: progressRef,
                                                    merge: true)
                            // Note: Cache update moved outside transaction
                        }
                        
                        return (true, isDaily, updatedHints, existingProgress) // Return data for cache update
                        
                    } catch {
                        errorPointer?.pointee = NSError(
                            domain: "purchaseHint",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
                        )
                        return false
                    }
                }
                
                // Handle transaction result
                guard let resultTuple = result as? (success: Bool, isDaily: Bool, updatedHints: [Int], existingProgress: RiddleProgress?) else {
                    return false
                }
                if !resultTuple.success { return false }
                
                // Update cache on main thread after transaction
                if !isTimerChallenge {
                    let newProgress = self.buildRiddleProgress(
                        existing: resultTuple.existingProgress,
                        riddleId: riddleId,
                        updatedHints: resultTuple.updatedHints
                    )
                    await MainActor.run {
                        if resultTuple.isDaily {
                            self.dailyProgressCache[riddleId] = newProgress
                        } else {
                            self.progressCache[riddleId] = newProgress
                        }
                    }
                }
            }
            
            // MARK: - 2. FREE HINTS (no coins)
            else {
                if isTimerChallenge,
                   let idx = riddleIndex,
                   idx >= 0, idx < 3 {
                    try await updateTimerChallengeHint(
                        userRef: userRef,
                        riddleId: riddleId,
                        hintIndex: hintIndex,
                        riddleIndex: idx,
                        todayStr: todayStr
                    )
                }
                else if isDaily {
                    try await updateDailyHint(
                        userRef: userRef,
                        riddleId: riddleId,
                        hintIndex: hintIndex,
                        todayStr: todayStr
                    )
                }
                else {
                    try await updateStandardHint(
                        userRef: userRef,
                        riddleId: riddleId,
                        hintIndex: hintIndex
                    )
                }
            }
            
            // Refresh coins
            await UserViewModel.shared.refreshCoins()
            return true
            
        } catch {
            print("purchaseHint failed: \(error)")
            return false
        }
    }
    
    
    func getTodayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
    
    func buildUpdatedHintIndices(current: [Int], newHint: Int) -> [Int] {
        return Array(Set(current + [newHint])).sorted()
    }
    
    func buildRiddleProgress(
        existing: RiddleProgress?,
        riddleId: String,
        updatedHints: [Int]
    ) -> RiddleProgress {
        return RiddleProgress(
            riddleId: riddleId,
            isCorrect: existing?.isCorrect ?? false,
            attempts: existing?.attempts ?? 0,
            usedHints: updatedHints.count,
            lastSeen: Date(),
            solvedDate: existing?.solvedDate,
            coinsEarned: existing?.coinsEarned ?? 0,
            revealedHintIndices: updatedHints
        )
    }
    
    
    
    func updateStandardHintTransaction(
        transaction: Transaction,
        progressRef: DocumentReference,
        riddleId: String,
        hintIndex: Int
    ) throws {
        
        let doc = try transaction.getDocument(progressRef)
        let existing = try? doc.data(as: RiddleProgress.self)
        let updated = buildUpdatedHintIndices(current: existing?.revealedHintIndices ?? [], newHint: hintIndex)
        
        let newProgress = buildRiddleProgress(existing: existing, riddleId: riddleId, updatedHints: updated)
        
        try transaction.setData(from: newProgress, forDocument: progressRef, merge: true)
        
        progressCache[riddleId] = newProgress
    }
    
    
    func updateDailyHintTransaction(
        transaction: Transaction,
        progressRef: DocumentReference,
        riddleId: String,
        hintIndex: Int
    ) throws {
        
        let doc = try transaction.getDocument(progressRef)
        let existing = try? doc.data(as: RiddleProgress.self)
        let updated = buildUpdatedHintIndices(current: existing?.revealedHintIndices ?? [], newHint: hintIndex)
        
        let newProgress = buildRiddleProgress(existing: existing, riddleId: riddleId, updatedHints: updated)
        
        try transaction.setData(from: newProgress, forDocument: progressRef, merge: true)
        
        dailyProgressCache[riddleId] = newProgress
    }
    
    
    func updateTimerChallengeHintTransaction(
        transaction: Transaction,
        progressRef: DocumentReference,
        riddleId: String,
        hintIndex: Int,
        riddleIndex: Int
    ) throws {
        
        let field = "revealedHintIndicesRiddle\(getRiddleStr(index: riddleIndex + 1))"
        let hintsField = "hintsUsedRiddle\(getRiddleStr(index: riddleIndex + 1))"
        
        let doc = try transaction.getDocument(progressRef)
        let existing = doc.data()?[field] as? [Int] ?? []
        let updated = buildUpdatedHintIndices(current: existing, newHint: hintIndex)
        
        transaction.updateData([
            field: updated,
            hintsField: updated.count
        ], forDocument: progressRef)
        
        let cache = timerProgressCache[riddleId] ?? TimerChallengeProgress(
            riddleId: riddleId,
            isCorrect: false,
            attempts: 0,
            usedHints: 0,
            lastSeen: Date(),
            revealedHintIndices: []
        )
        
        timerProgressCache[riddleId] = TimerChallengeProgress(
            riddleId: riddleId,
            isCorrect: cache.isCorrect,
            attempts: cache.attempts,
            usedHints: updated.count,
            lastSeen: Date(),
            revealedHintIndices: updated
        )
    }
    
    
    func updateStandardHint(
        userRef: DocumentReference,
        riddleId: String,
        hintIndex: Int
    ) async throws {
        
        let progressRef = userRef.collection("riddleProgress").document(riddleId)
        let doc = try await progressRef.getDocument()
        
        let existing = try? doc.data(as: RiddleProgress.self)
        let updated = buildUpdatedHintIndices(current: existing?.revealedHintIndices ?? [], newHint: hintIndex)
        
        let newProgress = buildRiddleProgress(existing: existing, riddleId: riddleId, updatedHints: updated)
        
        try progressRef.setData(from: newProgress, merge: true)
        
        progressCache[riddleId] = newProgress
    }
    
    
    func updateDailyHint(
        userRef: DocumentReference,
        riddleId: String,
        hintIndex: Int,
        todayStr: String
    ) async throws {
        
        let progressRef = userRef.collection("dailychallengeprogress").document(todayStr)
        let doc = try await progressRef.getDocument()
        
        let existing = try? doc.data(as: RiddleProgress.self)
        let updated = buildUpdatedHintIndices(current: existing?.revealedHintIndices ?? [], newHint: hintIndex)
        
        let newProgress = buildRiddleProgress(existing: existing, riddleId: riddleId, updatedHints: updated)
        
        try progressRef.setData(from: newProgress, merge: true)
        
        dailyProgressCache[riddleId] = newProgress
    }
    
    
    func updateTimerChallengeHint(
        userRef: DocumentReference,
        riddleId: String,
        hintIndex: Int,
        riddleIndex: Int,
        todayStr: String
    ) async throws {
        
        let progressRef = userRef.collection("timerDailyChallengeProgress").document(todayStr)
        let field = "revealedHintIndicesRiddle\(getRiddleStr(index: riddleIndex + 1))"
        let hintsField = "hintsUsedRiddle\(getRiddleStr(index: riddleIndex + 1))"
        
        let doc = try await progressRef.getDocument()
        let existingIndices = doc.data()?[field] as? [Int] ?? []
        let updated = buildUpdatedHintIndices(current: existingIndices, newHint: hintIndex)
        
        try await progressRef.setData([
            field: updated,
            hintsField: updated.count
        ], merge: true)
        
        // Update cache
        let existingCache = timerProgressCache[riddleId] ?? TimerChallengeProgress(
            riddleId: riddleId,
            isCorrect: false,
            attempts: 0,
            usedHints: 0,
            lastSeen: Date(),
            revealedHintIndices: []
        )
        
        timerProgressCache[riddleId] = TimerChallengeProgress(
            riddleId: riddleId,
            isCorrect: existingCache.isCorrect,
            attempts: existingCache.attempts,
            usedHints: updated.count,
            lastSeen: Date(),
            revealedHintIndices: updated
        )
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
