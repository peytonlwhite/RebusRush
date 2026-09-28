import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
final class UserViewModel: ObservableObject {
    static let shared = UserViewModel()
    
    @Published var currentUser: User?
    @Published var isLoggedIn = false
    @Published var uid: String = "guest"
    @Published var dailyChallengeStreak: Int = 0
    @Published var dailyChallengeLastSolved: Date?
    @Published var timerChallengeStreak: Int = 0
    @Published var timerChallengeLastSolved: Date?
    @Published var coins = 0
    @Published var preferredFilter: String = "all" // NEW: Store filter preference
    @Published var hasTimerChallengeProgress: Bool = false // NEW: Indicates if progress exists for today
    
    private let db = Firestore.firestore()
    private var listener: AuthStateDidChangeListenerHandle?
    
    private var signInTask: Task<Void, Error>?
    var isChangingAccount = false

    func adoptAccount(_ user: User) async throws {
        if let signInTask { try await signInTask.value }
        try await ensureUserDocumentExists(for: user.uid)
        currentUser = user
        uid = user.uid
        await loadUserData()
        isLoggedIn = true
    }

    func startFreshSession() async throws {
        isLoggedIn = false
        uid = "guest"
        try await signInAnonymously()
    }

    private init() {
        startAuthListener()
    }

    private func ensureUserDocumentExists(for userId: String) async throws {
        let userRef = db.collection("users").document(userId)
        _ = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(userRef)
                if !snapshot.exists {
                    transaction.setData(["coins": 300, "dailyChallengeStreak": 0,
                        "timerChallengeStreak": 0, "preferredFilter": "All"], forDocument: userRef)
                }
                return true
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    func signInAnonymously() async throws {
        if let signInTask { return try await signInTask.value }
        if isLoggedIn, Auth.auth().currentUser?.uid == uid { return }
        let task = Task { @MainActor in
            let user: User
            if let existing = Auth.auth().currentUser { user = existing }
            else { user = try await Auth.auth().signInAnonymously().user }
            // Do not expose gameplay until the starting balance exists.
            try await ensureUserDocumentExists(for: user.uid)
            currentUser = user
            uid = user.uid
            await loadUserData()
            isLoggedIn = true
        }
        signInTask = task
        defer { signInTask = nil }
        try await task.value
    }

    @MainActor
    func refreshCoins() async {
        guard !uid.isEmpty, uid != "guest" else { return }
        do {
            let docRef = db.collection("users").document(uid)
            let doc = try await docRef.getDocument()
            if let data = doc.data() {
                self.coins = data["coins"] as? Int ?? 0
                print("UserViewModel: Refreshed coins: \(self.coins)")
            }
        } catch {
            print("UserViewModel: Error refreshing coins: \(error)")
        }
    }
    
    func deductCoins(amount: Int) async -> Bool {
        guard !uid.isEmpty, uid != "guest" else { return false }
        guard coins >= amount else {
            print("UserViewModel: Insufficient coins (\(coins) < \(amount))")
            return false
        }
        
        do {
            let userRef = db.collection("users").document(uid)
            try await userRef.updateData(["coins": FieldValue.increment(Int64(-amount))])
            await refreshCoins()
            print("UserViewModel: Deducted \(amount) coins, new total: \(coins)")
            return true
        } catch {
            print("UserViewModel: Error deducting coins: \(error)")
            return false
        }
    }
    
    private func startAuthListener() {
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard self?.isChangingAccount != true else { return }
                if user != nil {
                    try? await self?.signInAnonymously()
                } else {
                    self?.currentUser = nil
                    self?.isLoggedIn = false
                    self?.uid = "guest"
                    self?.hasTimerChallengeProgress = false
                    self?.dailyChallengeStreak = 0
                    self?.dailyChallengeLastSolved = nil
                    self?.timerChallengeStreak = 0
                    self?.timerChallengeLastSolved = nil
                    self?.coins = 0
                    self?.preferredFilter = "all" // NEW: Reset filter
                }
            }
        }
    }
    
    func loadHasTimerProgress() async {
        guard !uid.isEmpty, uid != "guest" else { return }
        
        let docRef = db.collection("users")
            .document(uid)
            .collection("timerDailyChallengeProgress")
            .document(Date.utcDayString) // This is perfect

        do {
            let doc = try await docRef.getDocument()
            hasTimerChallengeProgress = doc.exists
        } catch {
            print("Failed to load timer progress: \(error)")
        }
    }
    
    func loadUserData() async {
            guard !uid.isEmpty, uid != "guest" else { return }

            do {
                let docRef = db.collection("users").document(uid)
                let doc = try await docRef.getDocument()
                if let data = doc.data() {
                    self.dailyChallengeStreak = data["dailyChallengeStreak"] as? Int ?? 0
                    self.dailyChallengeLastSolved = (data["dailyChallengeLastSolved"] as? Timestamp)?.dateValue()
                    self.timerChallengeStreak = data["timerChallengeStreak"] as? Int ?? 0
                    self.timerChallengeLastSolved = (data["timerChallengeLastSolved"] as? Timestamp)?.dateValue()
                    self.coins = data["coins"] as? Int ?? 0
                    self.preferredFilter = data["preferredFilter"] as? String ?? "all"
                }

                await loadHasTimerProgress()

                await resetStreakIfNeeded()
                await resetTimerChallengeStreakIfNeeded()
            } catch {
                print("Error loading user data: \(error)")
            }
        }
    
    func updateTimerChallengeStreak(completedToday: Bool, date: Date = Date()) async {
        if completedToday {
            await recordChallengeSolve(streakField: "timerChallengeStreak", dateField: "timerChallengeLastSolved", date: date)
        } else {
            await resetTimerChallengeStreakIfNeeded()
        }
    }
  
    
    func resetTimerChallengeStreakIfNeeded() async {
        guard let lastSolved = timerChallengeLastSolved else {
            timerChallengeStreak = 0
            return
        }

        // If they already completed TODAY → do nothing (streak continues)
        if lastSolved.isTodayUTC {
            return
        }

        // If they completed YESTERDAY → keep streak alive
        if lastSolved.isYesterdayUTC {
            return
        }

        // Expiry is a display calculation. A stale read must not erase a newer server win.
        timerChallengeStreak = 0
    }

    func updateStreak(completedToday: Bool, date: Date = Date()) async {
        if completedToday {
            await recordChallengeSolve(streakField: "dailyChallengeStreak", dateField: "dailyChallengeLastSolved", date: date)
        } else {
            await resetStreakIfNeeded()
        }
    }

    private func recordChallengeSolve(streakField: String, dateField: String, date: Date) async {
        guard !uid.isEmpty, uid != "guest" else { return }
        let now = date
        let userRef = db.collection("users").document(uid)
        do {
            let result = try await db.runTransaction { transaction, errorPointer -> Any? in
                do {
                    let data = try transaction.getDocument(userRef).data() ?? [:]
                    if let last = (data[dateField] as? Timestamp)?.dateValue(),
                       GameRules.utcCalendar.startOfDay(for: last) > GameRules.utcCalendar.startOfDay(for: now) {
                        return nil // A late completion must not move a newer streak backward.
                    }
                    let next = GameRules.streakAfterSolve(
                        current: data[streakField] as? Int ?? 0,
                        lastSolved: (data[dateField] as? Timestamp)?.dateValue(), now: now)
                    transaction.setData([streakField: next, dateField: Timestamp(date: now)],
                                        forDocument: userRef, merge: true)
                    return next
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            guard let next = result as? Int else { return }
            if streakField == "dailyChallengeStreak" {
                dailyChallengeStreak = next
                dailyChallengeLastSolved = now
            } else {
                timerChallengeStreak = next
                timerChallengeLastSolved = now
            }
        } catch {
            print("Error recording challenge streak: \(error)")
        }
    }

    private func resetStreakIfNeeded() async {
        guard let lastSolved = dailyChallengeLastSolved else {
            dailyChallengeStreak = 0
            return
        }

        // If solved today → streak continues
        if lastSolved.isTodayUTC {
            return
        }

        // If solved yesterday → keep streak
        if lastSolved.isYesterdayUTC {
            return
        }

        dailyChallengeStreak = 0
    }

    // NEW: Save preferred filter
    func savePreferredFilter(_ filter: String) async {
        guard !uid.isEmpty, uid != "guest" else { return }
        do {
            try await db.collection("users").document(uid).setData([
                "preferredFilter": filter
            ], merge: true)
            preferredFilter = filter
            print("UserViewModel: Saved preferredFilter: \(filter)")
        } catch {
            print("UserViewModel: Error saving preferredFilter: \(error)")
            preferredFilter = "all" // Fallback
        }
    }
    
    func resetGame() async {
            guard !uid.isEmpty, uid != "guest" else { return }

            do {
                let userRef = db.collection("users").document(uid)
                try await userRef.updateData([
                    "coins": 300
                ])

                let progressRef = userRef.collection("riddleProgress")
                let docs = try await progressRef.getDocuments()
                for doc in docs.documents {
                    try await doc.reference.delete()
                }

                let timerProgressRef = userRef.collection("timerDailyChallengeProgress")
                let timerDocs = try await timerProgressRef.getDocuments()
                for doc in timerDocs.documents {
                    try await doc.reference.delete()
                }

                await refreshCoins()
                hasTimerChallengeProgress = false
                print("UserViewModel: Game reset - coins set to 300, riddleProgress and timerDailyChallengeProgress cleared")
            } catch {
                print("UserViewModel: Error resetting game: \(error)")
            }
        }
    
    func progressCollection() -> CollectionReference {
        db.collection("users").document(uid).collection("riddleProgress")
    }
    
    deinit {
        if let listener { Auth.auth().removeStateDidChangeListener(listener) }
    }
}



extension Date {
    /// Returns "yyyy-MM-dd" string in UTC — perfect for Firestore daily document IDs
    static var utcDayString: String {
        DateFormatter.utcDayFormatter.string(from: Date())
    }
    
    /// Returns "yyyy-MM-dd" UTC string for any date
    var utcDayString: String {
        DateFormatter.utcDayFormatter.string(from: self)
    }
    
    /// Returns true if this date falls on the same calendar day (in UTC) as today
    var isTodayUTC: Bool {
        self.utcDayString == Date.utcDayString
    }
    
    /// Returns true if this date is yesterday in UTC (used for streak logic)
    var isYesterdayUTC: Bool {
        let yesterday = GameRules.utcCalendar.date(byAdding: .day, value: -1, to: Date())!
        return self.utcDayString == yesterday.utcDayString
    }
}

extension DateFormatter {
    static let utcDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX") // Prevents locale bugs
        return formatter
    }()
}
