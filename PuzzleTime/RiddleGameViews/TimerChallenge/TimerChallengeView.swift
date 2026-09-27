import SwiftUI
import FirebaseFirestore
import ConfettiSwiftUI

struct TimerChallengeView: View {
    @ObservedObject var viewModel: RiddleViewModel
    @EnvironmentObject var userVM: UserViewModel
    @Environment(\.dismiss) var dismiss
    @State private var currentRiddleIndex: Int = 0
    @State private var timerSeconds: Int = 180
    @State private var isTimerRunning: Bool = false
    @State private var userAnswers: [Int: String] = [:]
    @State private var results: [Int: String] = [:]
    @State private var isLoading: [Int: Bool] = [:]
    @State private var isAdLoading = false
    @State private var revealedHints: [Int: Int] = [:]
    @State private var showingHintIndices: [Int: Set<Int>] = [:]
    @State private var pandaWave: Bool = false
    @State private var confettiTrigger: Int = 0
    @State private var coinPop: Int = 0
    @State private var showExitAlert: Bool = false
    @State private var showGameRecap: Bool = false
    @State private var showGameOver: Bool = false
    @State private var timer: Timer?
    @State private var riddleResults: [Int: Bool] = [:]
    @State private var hintsUsed: [Int: Int] = [:]
    @State private var isTransitioning: Bool = false
    @State private var hasSavedProgress: Bool = false
    @State private var attempts: [Int: Int] = [:]
    @State private var isSaving: Bool = false // Prevent concurrent saves
    @State private var isLoadingProgress: Bool = true // NEW: Track progress loading to prevent races
    @Binding var path: NavigationPath // Add path binding
    @State var lastAnsweredRiddleId: String = ""

    private let evaluator = RiddleEvaluator()
    private let totalTime: Int = 180
    
    var body: some View {
        DarkModeWrapper {
            ZStack {
                BackgroundGradient()
                
                PandaBehindImage(pandaPeek: .constant(1), isWaving: $pandaWave)
                
                if viewModel.timerRiddles.isEmpty || isLoadingProgress { // CHANGED: Hide start screen until fully loaded
                    ProgressView("Loading timer riddles...")
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                } else {
                    VStack(spacing: 0) {
                        // Header with coins and timer
                        HStack {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundColor(.yellow)
                            Text("Coins: \(userVM.coins)")
                                .font(.headline)
                            Spacer()
                            Text(timerDisplay)
                                .font(.title2.bold())
                                .foregroundColor(timerSeconds > 30 ? .cyan : .red)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        
                        // Riddle content or start screen
                        if !hasSavedProgress && !isTimerRunning {
                            startScreen
                        } else {
                            VStack(spacing: 0) {
                                carouselTabView
                                pageDots
                            }
                        }
                        
                        Spacer()
                    }
                }
                
                
            
                
                if coinPop > 0 {
                    Text("+\(coinPop) coins!")
                        .font(.title2).bold()
                        .foregroundColor(.yellow)
                        .padding(10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .offset(y: -100)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(1)
                }
                
                ConfettiLayer(trigger: $confettiTrigger)
                
                AdLoadingOverlay(isAdLoading: $isAdLoading)

            }
            .navigationTitle("Timer Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task { @MainActor in
                    print("onAppear: Loading timer riddles and progress") // Debug log
                    await viewModel.loadTimerDailyRiddles()
                    await loadSavedProgress()
                    isLoadingProgress = false // NEW: Set after all awaits complete
                }
            }
            .onDisappear {
                if isTimerRunning && !showGameRecap && !showGameOver && !isSaving {
                    timer?.invalidate()
                    Task { @MainActor in
                        isSaving = true
                        print("onDisappear: Saving progress") // Debug log
                        await saveProgress(completed: false)
                        isSaving = false
                    }
                }
            }
            .alert("Exit Challenge?", isPresented: $showExitAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Exit", role: .destructive) { dismiss() }
            } message: {
                Text("Your progress will be saved, but the timer will continue when you return. Continue?")
            }
            .navigationDestination(isPresented: $showGameRecap) {
                GameRecapView(
                    timeTaken: totalTime - timerSeconds,
                    results: riddleResults,
                    hintsUsed: hintsUsed,
                    riddles: viewModel.timerRiddles,
                    path: $path
                )
                .environmentObject(userVM)
            }
            .navigationDestination(isPresented: $showGameOver) {
                GameOverView(
                    results: riddleResults,
                    hintsUsed: hintsUsed,
                    riddles: viewModel.timerRiddles,
                    path: $path
                )
                .environmentObject(userVM)
            }
            .onChange(of: currentRiddleIndex) { newIndex in
                print("Riddle index changed to \(newIndex)") // Debug log
                withAnimation(.easeInOut(duration: 0.45)) {
                    isTransitioning = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        isTransitioning = false
                    }
                }
            }
            .onChange(of: viewModel.isTimerPaused) { isPaused in
                if isPaused && isTimerRunning {
                    print("Pausing timer due to external pause (e.g., ad)")
                    timer?.invalidate()
                    isTimerRunning = false
                } else if !isPaused && !isTimerRunning && timerSeconds > 0 && !riddleResults.values.allSatisfy({ $0 }) {
                    print("Resuming timer due to external resume")
                    isTimerRunning = true
                    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        Task { @MainActor in
                            if timerSeconds > 0 {
                                timerSeconds -= 1
                                if timerSeconds % 5 == 0 && !isSaving {
                                    isSaving = true
                                    print("Periodic save at \(timerSeconds) seconds, riddleResults = \(riddleResults)")
                                    await saveProgress(completed: false)
                                    isSaving = false
                                }
                            } else {
                                timer?.invalidate()
                                isTimerRunning = false
                                isSaving = true
                                print("Time out save, riddleResults = \(riddleResults)")
                                await saveProgress(completed: false)
                                isSaving = false
                                showGameOver = true
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var startScreen: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Timer Challenge")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.cyan)
            Text("Solve 3 riddles in 3 minutes! 🏅")
                .font(.title3)
                .foregroundColor(.white)
            Button(action: { Task { await startChallenge() } }) {
                Text("Start")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(
                        Capsule()
                            .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 2))
                    )
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }
    
    private var carouselTabView: some View {
        TabView(selection: $currentRiddleIndex) {
            ForEach(viewModel.timerRiddles.indices, id: \.self) { index in
                riddleContentView(for: viewModel.timerRiddles[index], at: index)
                    .tag(index)
                    .padding(.horizontal, 8)
                    .opacity(currentRiddleIndex == index ? 1 : 0.3)
                    .blur(radius: currentRiddleIndex == index ? 0 : 5)
                    .animation(.easeInOut(duration: 0.3), value: currentRiddleIndex)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .transition(.opacity)
        .animation(.easeInOut, value: currentRiddleIndex)
    }
    
    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.timerRiddles.indices, id: \.self) { idx in
                Circle()
                    .fill(riddleResults[idx] == true ? Color.green : (idx == currentRiddleIndex ? Color.cyan : Color.secondary.opacity(0.4)))
                    .frame(width: 9, height: 9)
                    .scaleEffect(idx == currentRiddleIndex ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3), value: currentRiddleIndex)
                    .animation(.spring(response: 0.3), value: riddleResults[idx])
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 20)
    }
    
    private func riddleContentView(for riddle: Riddle, at index: Int) -> some View {
        RiddleContent(
            riddle: riddle,
            progress: viewModel.timerProgressCache[riddle.uiId],
            userAnswer: Binding(
                get: { userAnswers[index] ?? "" },
                set: { userAnswers[index] = $0 }
            ),
            result: Binding(
                get: { results[index] ?? "" },
                set: { results[index] = $0 }
            ),
            isLoading: Binding(
                get: { isLoading[index] ?? false },
                set: { isLoading[index] = $0 }
            ),
            revealedHints: Binding(
                get: { revealedHints[index] ?? 0 },
                set: { revealedHints[index] = $0 }
            ),
            pandaWave: $pandaWave,
            viewModel: viewModel,
            showingHintIndices: Binding(
                get: { showingHintIndices[index] ?? [] },
                set: { showingHintIndices[index] = $0 }
            ),
            isTransitioning: $isTransitioning,
            isDailyMode: false,
            isTimerChallenge: true,
            riddleIndex: index,
            onSubmit: { usedHints in
                Task { await submit(riddle: riddle, index: index, usedHints: usedHints) }
            },
            isAdLoading: $isAdLoading,
            lastAnsweredRiddleId: $lastAnsweredRiddleId
        )
    }
    
    private var timerDisplay: String {
        let minutes = timerSeconds / 60
        let seconds = timerSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    @MainActor
    private func startChallenge() async {
        guard userVM.isLoggedIn else {
            print("startChallenge: User not logged in")
            return
        }
        // Prevent starting a new timer if one is already running
        guard !isTimerRunning else {
            print("startChallenge: Timer already running, skipping")
            return
        }
        isTimerRunning = true
        timer?.invalidate() // Ensure no stale timers
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                if timerSeconds > 0 && !viewModel.isTimerPaused {
                    timerSeconds -= 1
                    if timerSeconds % 5 == 0 && !isSaving {
                        isSaving = true
                        print("Periodic save at \(timerSeconds) seconds, riddleResults = \(riddleResults)")
                        await saveProgress(completed: false)
                        isSaving = false
                    }
                } else if timerSeconds <= 0 {
                    timer?.invalidate()
                    isTimerRunning = false
                    isSaving = true
                    print("Time out save, riddleResults = \(riddleResults)")
                    await saveProgress(completed: false)
                    isSaving = false
                    showGameOver = true
                }
            }
        }
      
        
        let todayStr = Date.utcDayString
        
        // Load timer challenge progress from RiddleViewModel
        await viewModel.loadTimerChallengeProgress(for: userVM.uid)
        let hasProgress = !viewModel.timerProgressCache.isEmpty || userVM.hasTimerChallengeProgress
        if !hasProgress && !hasSavedProgress {
            isSaving = true
            print("Initial save for new challenge, riddleResults = \(riddleResults)")
            await viewModel.saveTimerChallengeProgress(
                userId: userVM.uid,
                date: Date(),
                played: true,
                completed: false,
                timeRemaining: timerSeconds,
                timeTakenSeconds: 0,
                riddleResults: [:],
                hintsUsed: [:],
                revealedHintIndices: [:],
                attempts: [:]
            )
            // Update hasTimerChallengeProgress in UserViewModel
            do {
                try await Firestore.firestore().collection("users").document(userVM.uid).setData(
                    ["hasTimerChallengeProgress": true],
                    merge: true
                )
                userVM.hasTimerChallengeProgress = true
                print("startChallenge: Set hasTimerChallengeProgress to true")
            } catch {
                print("startChallenge: Failed to update hasTimerChallengeProgress: \(error)")
            }
            hasSavedProgress = true
            isSaving = false
        } else {
            print("startChallenge: Progress already exists, skipping initial save")
        }
    }
    
    @MainActor
    private func submit(riddle: Riddle, index: Int, usedHints: Int) async {
        let input = (userAnswers[index] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !input.isEmpty else {
            print("submit: Empty input, returning")
            return
        }
        // Pause the timer
        timer?.invalidate()
        isTimerRunning = false
        isLoading[index] = true
        results[index] = ""
        lastAnsweredRiddleId = "nil"  // ← Reset

        let db = Firestore.firestore()
        do {
            let verdict = try await evaluator.evaluate(userAnswer: input, riddle: riddle)
            let isCorrect = verdict == "correct"
            lastAnsweredRiddleId = riddle.uiId  // ← This is the key!

            let newAttempts = (attempts[index] ?? 0) + 1
            riddleResults[index] = isCorrect
            hintsUsed[index] = usedHints
            attempts[index] = newAttempts
            let coinsEarned = isCorrect ? max(0, 50 - usedHints * 10) : 0
            results[index] = verdict
            if isCorrect {
                pandaWave = true
                confettiTrigger += 1
                withAnimation(.spring()) {
                    coinPop = coinsEarned
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    pandaWave = false
                    coinPop = 0
                }
                userAnswers[index] = ""
            }
            isLoading[index] = false
            // Save progress to Firestore
            isSaving = true
            print("Saving progress after submission for riddle \(index), riddleResults = \(riddleResults)")
            await viewModel.saveTimerChallengeProgress(
                userId: userVM.uid,
                date: Date(),
                played: true,
                completed: riddleResults.count == viewModel.timerRiddles.count && riddleResults.values.allSatisfy({ $0 }),
                timeRemaining: timerSeconds > 0 ? timerSeconds : nil,
                timeTakenSeconds: totalTime - timerSeconds,
                riddleResults: riddleResults,
                hintsUsed: hintsUsed,
                revealedHintIndices: Dictionary(uniqueKeysWithValues: viewModel.timerRiddles.indices.map { ($0, Array(showingHintIndices[$0] ?? [])) }),
                attempts: attempts
            )
            isSaving = false
            if isCorrect && coinsEarned > 0 {
                try await db.collection("users").document(userVM.uid).updateData(["coins": FieldValue.increment(Int64(coinsEarned))])
                await userVM.refreshCoins()
            }
            // Resume timer if game is not over
            let isGameCompleted = riddleResults.count == viewModel.timerRiddles.count && riddleResults.values.allSatisfy({ $0 })
            if !isGameCompleted && timerSeconds > 0 {
                print("Resuming timer after submission, timeRemaining = \(timerSeconds)")
                isTimerRunning = true
                timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    Task { @MainActor in
                        if timerSeconds > 0 {
                            timerSeconds -= 1
                            if timerSeconds % 5 == 0 && !isSaving {
                                isSaving = true
                                print("Periodic save at \(timerSeconds) seconds, riddleResults = \(riddleResults)")
                                await saveProgress(completed: false)
                                isSaving = false
                            }
                        } else {
                            timer?.invalidate()
                            isTimerRunning = false
                            isSaving = true
                            print("Time out save, riddleResults = \(riddleResults)")
                            await saveProgress(completed: false)
                            isSaving = false
                            showGameOver = true
                        }
                    }
                }
            }
            // Check if all riddles are solved
            if isGameCompleted {
                timer?.invalidate()
                isTimerRunning = false
                isSaving = true
                print("Game completed save, riddleResults = \(riddleResults)")
                await saveProgress(completed: true)
                isSaving = false
                showGameRecap = true
            }
            // Update timerProgressCache
            viewModel.timerProgressCache[riddle.uiId] = TimerChallengeProgress(
                riddleId: riddle.uiId,
                isCorrect: isCorrect,
                attempts: newAttempts,
                usedHints: usedHints,
                lastSeen: Date(),
                revealedHintIndices: Array(showingHintIndices[index] ?? [])
            )
        } catch {
            results[index] = "error"
            isLoading[index] = false
            // Resume timer if game is not over
            if timerSeconds > 0 {
                print("Resuming timer after error, timeRemaining = \(timerSeconds)")
                isTimerRunning = true
                timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    Task { @MainActor in
                        if timerSeconds > 0 {
                            timerSeconds -= 1
                            if timerSeconds % 5 == 0 && !isSaving {
                                isSaving = true
                                print("Periodic save at \(timerSeconds) seconds, riddleResults = \(riddleResults)")
                                await saveProgress(completed: false)
                                isSaving = false
                            }
                        } else {
                            timer?.invalidate()
                            isTimerRunning = false
                            isSaving = true
                            print("Time out save, riddleResults = \(riddleResults)")
                            await saveProgress(completed: false)
                            isSaving = false
                            showGameOver = true
                        }
                    }
                }
            }
            print("Evaluation failed: \(error)")
        }
    }
    
    @MainActor
    private func saveProgress(completed: Bool) async {
        let medal = completed ? determineMedal() : nil
        print("Saving progress: riddleResults = \(riddleResults), completed = \(completed), timeRemaining = \(timerSeconds)") // Debug log
        await viewModel.saveTimerChallengeProgress(
            userId: userVM.uid,
            date: Date(),
            played: true,
            completed: completed,
            timeRemaining: completed || timerSeconds <= 0 ? nil : timerSeconds,
            timeTakenSeconds: totalTime - timerSeconds,
            riddleResults: riddleResults,
            hintsUsed: hintsUsed,
            revealedHintIndices: Dictionary(uniqueKeysWithValues: viewModel.timerRiddles.indices.map { ($0, Array(showingHintIndices[$0] ?? [])) }),
            attempts: attempts
        )
        // Optionally update Firestore with medal if completed
        if completed, let medal = medal {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            let dateStr = formatter.string(from: Date())
            let progressRef = Firestore.firestore().collection("users").document(userVM.uid).collection("timerDailyChallengeProgress").document(dateStr)
            do {
                try await progressRef.setData(["medal": medal], merge: true)
                print("Saved medal: \(medal) for date \(dateStr)")
            } catch {
                print("Failed to save medal: \(error)")
            }
        }
    }
    
    @MainActor
    private func loadSavedProgress() async {
       
        let todayStr = Date.utcDayString
        // Ensure timerRiddles are loaded
        if viewModel.timerRiddles.isEmpty {
            print("loadSavedProgress: Loading timer riddles")
            await viewModel.loadTimerDailyRiddles()
        }
        // Fetch timer progress from RiddleViewModel
        print("loadSavedProgress: Loading timer challenge progress")
        await viewModel.loadTimerChallengeProgress(for: userVM.uid)
        
        if viewModel.timerRiddles.isEmpty {
            print("loadSavedProgress: Setting ultimate fallback timer riddles")
            viewModel.timerRiddles = Array(viewModel.riddles.prefix(3))
        }
        
        // Check if progress exists
        let hasProgress = !viewModel.timerProgressCache.isEmpty
        hasSavedProgress = hasProgress // CHANGED: Set explicitly here
        guard hasProgress else {
            print("loadSavedProgress: No progress found for today: \(todayStr)")
            timerSeconds = totalTime // NEW: Explicit for new challenges
            return // CHANGED: Don't auto-start for new; wait for user click
        }
        print("loadSavedProgress: Found progress in timerProgressCache: \(viewModel.timerProgressCache)")
        // Load time remaining from Firestore directly (since timerProgressCache doesn't store it)
        let progressRef = Firestore.firestore().collection("users").document(userVM.uid).collection("timerDailyChallengeProgress").document(todayStr)
        let doc = try? await progressRef.getDocument()
        let savedTime = doc?.data()?["timeRemaining"] as? Int
        timerSeconds = hasProgress ? (savedTime ?? 0) : totalTime // CHANGED: Handle nil as 0 if progress exists (timeout/complete)
        print("loadSavedProgress: Loaded timeRemaining: \(timerSeconds)")
        // Clear state to avoid stale data
        riddleResults.removeAll()
        hintsUsed.removeAll()
        attempts.removeAll()
        revealedHints.removeAll()
        showingHintIndices.removeAll()
        // Map progress to state variables
        for (index, riddle) in viewModel.timerRiddles.enumerated() {
            let riddleId = riddle.uiId
            guard let progress = viewModel.timerProgressCache[riddleId] else {
                riddleResults[index] = false // NEW: Explicitly set unsolved to false
                continue
            }
            riddleResults[index] = progress.isCorrect
            hintsUsed[index] = progress.usedHints
            attempts[index] = progress.attempts
            revealedHints[index] = progress.revealedHintIndices.count
            showingHintIndices[index] = Set(progress.revealedHintIndices)
            // Reset UI for unsolved riddles
            if !progress.isCorrect {
                userAnswers[index] = ""
                results[index] = ""
                isLoading[index] = false
            }
            print("loadSavedProgress: Loaded riddle \(index): isCorrect = \(progress.isCorrect), hintsUsed = \(progress.usedHints), attempts = \(progress.attempts)")
        }
        // Handle game state
        let isCompleted = doc?.data()?["completed"] as? Bool == true
        if isCompleted {
            timer?.invalidate()
            isTimerRunning = false
            showGameRecap = true
            print("loadSavedProgress: Game is completed, showing recap")
        } else if timerSeconds <= 0 {
            timer?.invalidate()
            isTimerRunning = false
            showGameOver = true
            print("loadSavedProgress: Time is up, showing game over")
        } else if !isTimerRunning {
            print("loadSavedProgress: Resuming challenge")
            await startChallenge() // CHANGED: Only resume if existing progress
        }
    }
    
    private func determineMedal() -> String? {
        let timeTaken = totalTime - timerSeconds
        if timeTaken <= 60 { return "Gold" }
        else if timeTaken <= 120 { return "Silver" }
        else { return "Bronze" }
    }
}
