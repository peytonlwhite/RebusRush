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
    
    private init() {
            startAuthListener()
            // Kick off user creation immediately — fire and forget (safe)
            Task {
                await ensureUserDocumentExists()
            }
        }
    
    private func ensureUserDocumentExists() async {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            
            let userRef = db.collection("users").document(uid)
            
            do {
                let doc = try await userRef.getDocument()
                if !doc.exists {
                    try await userRef.setData([
                        "coins": 300,
                        "dailyChallengeStreak": 0,
                        "dailyChallengeLastSolved": FieldValue.serverTimestamp(),
                        "timerChallengeStreak": 0,
                        "timerChallengeLastSolved": FieldValue.serverTimestamp(),
                        "preferredFilter": "all"
                    ])
                    print("User document created for UID: \(uid)")
                }
            } catch {
                print("Failed to create user document: \(error)")
            }
            
            await loadUserData() // Now safe to load
        }
    
    func signInAnonymously() async throws {
            if Auth.auth().currentUser != nil { return }
            
            let result = try await Auth.auth().signInAnonymously()
            await MainActor.run {
                self.currentUser = result.user
                self.isLoggedIn = true
                self.uid = result.user.uid
            }
            
            // This will create the doc if missing
            await ensureUserDocumentExists()
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
                self?.currentUser = user
                self?.isLoggedIn = user != nil
                self?.uid = user?.uid ?? "guest"
                if user != nil {
                    await self?.loadUserData()
                } else {
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
    
    func updateTimerChallengeStreak(completedToday: Bool) async {
            guard !uid.isEmpty, uid != "guest" else { return }

            let today = Calendar.current.startOfDay(for: Date())
            let docRef = db.collection("users").document(uid)

            if completedToday {
                let newStreak = timerChallengeStreak + 1
                do {
                    try await docRef.setData([
                        "timerChallengeStreak": newStreak,
                        "timerChallengeLastSolved": Timestamp(date: today)
                    ], merge: true)
                    timerChallengeStreak = newStreak
                    timerChallengeLastSolved = today
                } catch {
                    print("Error updating timer challenge streak: \(error)")
                }
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

        // Otherwise → missed a day → reset streak
        do {
            try await db.collection("users").document(uid).updateData([
                "timerChallengeStreak": 0,
                "timerChallengeLastSolved": FieldValue.delete()
            ])
            timerChallengeStreak = 0
            timerChallengeLastSolved = nil
        } catch {
            print("Error resetting timer challenge streak: \(error)")
        }
    }

        func updateStreak(completedToday: Bool) async {
            guard !uid.isEmpty, uid != "guest" else { return }

            let today = Calendar.current.startOfDay(for: Date())
            let docRef = db.collection("users").document(uid)

            if completedToday {
                let newStreak = dailyChallengeStreak + 1
                do {
                    try await docRef.setData([
                        "dailyChallengeStreak": newStreak,
                        "dailyChallengeLastSolved": Timestamp(date: today)
                    ], merge: true)
                    dailyChallengeStreak = newStreak
                    dailyChallengeLastSolved = today
                } catch {
                    print("Error updating streak: \(error)")
                }
            } else {
                await resetStreakIfNeeded()
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

        // Missed a day → reset
        do {
            try await db.collection("users").document(uid).updateData([
                "dailyChallengeStreak": 0,
                "dailyChallengeLastSolved": FieldValue.delete()
            ])
            dailyChallengeStreak = 0
            dailyChallengeLastSolved = nil
        } catch {
            print("Error resetting daily streak: \(error)")
        }
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
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
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
