import SwiftUI
import FirebaseFirestore
import ConfettiSwiftUI

struct TimerChallengeView: View {
    @ObservedObject var viewModel: RiddleViewModel
    @EnvironmentObject var userVM: UserViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isViewActive = false
    @State private var startError: String?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var challengeDate = Date()
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
                
                if isLoadingProgress {
                    ProgressView("Loading timer riddles...")
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                } else if loadError != nil || viewModel.timerRiddles.count != 3 {
                    VStack(spacing: 16) {
                        Text(loadError ?? "Couldn't load today's three puzzles.")
                        Button("Retry") {
                            Task {
                                isLoadingProgress = true
                                await loadSavedProgress()
                                isLoadingProgress = false
                            }
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        if let saveError {
                            VStack(spacing: 8) {
                                Text(saveError).multilineTextAlignment(.center)
                                Button("Retry Save") {
                                    Task {
                                        isSaving = true
                                        let complete = riddleResults.count == 3 && riddleResults.values.allSatisfy { $0 }
                                        let saved = await saveProgress(completed: complete)
                                        isSaving = false
                                        if saved {
                                            if complete { showGameRecap = true }
                                            else if timerSeconds == 0 { showGameOver = true }
                                            else { startTicker() }
                                        }
                                    }
                                }
                                .disabled(isSaving)
                            }
                            .padding()
                        }
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
                isViewActive = true
                viewModel.timerChallengeDate = challengeDate
                Task { @MainActor in
                    print("onAppear: Loading timer riddles and progress") // Debug log
                    await loadSavedProgress()
                    isLoadingProgress = false // NEW: Set after all awaits complete
                }
            }
            .onDisappear {
                isViewActive = false
                timer?.invalidate()
                isTimerRunning = false
                if hasSavedProgress && !showGameRecap && !showGameOver && !isSaving && !isLoading.values.contains(true) {
                    Task { @MainActor in
                        isSaving = true
                        print("onDisappear: Saving progress") // Debug log
                        await saveProgress(completed: false)
                        isSaving = false
                    }
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background, hasSavedProgress, !isSaving,
                   !isLoading.values.contains(true), !showGameRecap, !showGameOver {
                    Task {
                        isSaving = true
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
                } else if !isPaused && isViewActive && hasSavedProgress && !isLoading.values.contains(true) && !isTimerRunning && timerSeconds > 0 && !riddleResults.values.allSatisfy({ $0 }) {
                    print("Resuming timer due to external resume")
                    isTimerRunning = true
                    startTicker()
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
            if let startError {
                Text(startError).foregroundColor(.orange).multilineTextAlignment(.center)
            }
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
            .disabled(isSaving)
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
    private func startTicker() {
        timer?.invalidate()
        guard isViewActive, saveError == nil, timerSeconds > 0, viewModel.timerRiddles.count == 3 else {
            isTimerRunning = false
            return
        }
        isTimerRunning = true
        startError = nil
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                guard isViewActive, scenePhase == .active, !isAdLoading,
                      !viewModel.isTimerPaused, !isLoading.values.contains(true),
                      !isSaving else { return }
                timerSeconds = max(0, timerSeconds - 1)
                if timerSeconds == 0 {
                    timer?.invalidate()
                    isTimerRunning = false
                    isSaving = true
                    let saved = await saveProgress(completed: false)
                    isSaving = false
                    if saved { showGameOver = true }
                } else if timerSeconds % 5 == 0 {
                    isSaving = true
                    await saveProgress(completed: false)
                    isSaving = false
                }
            }
        }
    }

    @MainActor
    private func startChallenge() async {
        guard userVM.isLoggedIn, isViewActive, !isSaving, !isTimerRunning,
              loadError == nil, viewModel.timerRiddles.count == 3 else { return }
        if hasSavedProgress { startTicker(); return }
        isSaving = true
        startError = nil
        defer { isSaving = false }
        let saved = await viewModel.saveTimerChallengeProgress(
            userId: userVM.uid, date: challengeDate, played: true, completed: false,
            timeRemaining: totalTime, timeTakenSeconds: 0,
            riddleResults: [:], hintsUsed: [:], revealedHintIndices: [:], attempts: [:])
        guard saved != nil else {
            startError = "Couldn't save the challenge. Check your connection and tap Start to retry."
            return
        }
        userVM.hasTimerChallengeProgress = true
        hasSavedProgress = true
        if let data = viewModel.timerSavedData { restoreState(from: data) }
        if !showGameRecap && !showGameOver { startTicker() }
    }

    @MainActor
    private func submit(riddle: Riddle, index: Int, usedHints: Int) async {
        let input = (userAnswers[index] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !input.isEmpty, isViewActive, saveError == nil, timerSeconds > 0,
              !isSaving, !isLoading.values.contains(true),
              riddleResults[index] != true else {
            print("submit: Empty input, returning")
            return
        }
        // Pause the timer
        timer?.invalidate()
        isTimerRunning = false
        isLoading[index] = true
        defer { isLoading[index] = false }
        results[index] = ""
        lastAnsweredRiddleId = "nil"  // ← Reset

        do {
            let verdict = try await evaluator.evaluate(userAnswer: input, riddle: riddle)
            let isCorrect = verdict == "correct"
            lastAnsweredRiddleId = riddle.uiId  // ← This is the key!

            let newAttempts = (attempts[index] ?? 0) + 1
            riddleResults[index] = isCorrect
            let purchasedHints = viewModel.timerProgressCache[riddle.uiId]?.revealedHintIndices ?? []
            let hintCount = max(usedHints, purchasedHints.count)
            hintsUsed[index] = hintCount
            attempts[index] = newAttempts
            results[index] = verdict
            // Save progress to Firestore
            isSaving = true
            print("Saving progress after submission for riddle \(index), riddleResults = \(riddleResults)")
            let awardedCoins = await viewModel.saveTimerChallengeProgress(
                userId: userVM.uid,
                date: challengeDate,
                played: true,
                completed: riddleResults.count == viewModel.timerRiddles.count && riddleResults.values.allSatisfy({ $0 }),
                timeRemaining: timerSeconds > 0 ? timerSeconds : nil,
                timeTakenSeconds: totalTime - timerSeconds,
                riddleResults: riddleResults,
                hintsUsed: hintsUsed,
                revealedHintIndices: Dictionary(uniqueKeysWithValues: viewModel.timerRiddles.indices.map { ($0, Array(showingHintIndices[$0] ?? [])) }),
                attempts: attempts,
                rewardForRiddleIndex: index
            )
            isSaving = false
            guard let awardedCoins else {
                throw NSError(domain: "RebusRush", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Couldn't save your answer. Please try again."])
            }
            await userVM.refreshCoins()
            if let data = viewModel.timerSavedData { restoreState(from: data) }
            if isCorrect && riddleResults[index] == true {
                pandaWave = true
                confettiTrigger += 1
                withAnimation(.spring()) { coinPop = awardedCoins }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    pandaWave = false
                    coinPop = 0
                }
                userAnswers[index] = ""
            }
            // Resume timer if game is not over
            let isGameCompleted = riddleResults.count == viewModel.timerRiddles.count && riddleResults.values.allSatisfy({ $0 })
            if !isGameCompleted && timerSeconds > 0 && isViewActive {
                print("Resuming timer after submission, timeRemaining = \(timerSeconds)")
                isTimerRunning = true
                startTicker()
            }
            // Check if all riddles are solved
            if isGameCompleted {
                timer?.invalidate()
                isTimerRunning = false
                isSaving = true
                print("Game completed save, riddleResults = \(riddleResults)")
                let saved = await saveProgress(completed: true)
                isSaving = false
                if saved { showGameRecap = true }
            } else if timerSeconds == 0 {
                showGameOver = true
            }
        } catch {
            let saved = viewModel.timerProgressCache[riddle.uiId]
            riddleResults[index] = saved?.isCorrect ?? false
            attempts[index] = saved?.attempts ?? 0
            isSaving = false
            results[index] = "error"
            lastAnsweredRiddleId = riddle.uiId
            // Resume timer if game is not over
            if timerSeconds > 0 && isViewActive {
                print("Resuming timer after error, timeRemaining = \(timerSeconds)")
                isTimerRunning = true
                startTicker()
            }
            print("Evaluation failed: \(error)")
        }
    }
    
    @MainActor
    @discardableResult
    private func saveProgress(completed: Bool) async -> Bool {
        let medal = completed ? determineMedal() : nil
        print("Saving progress: riddleResults = \(riddleResults), completed = \(completed), timeRemaining = \(timerSeconds)") // Debug log
        let saved = await viewModel.saveTimerChallengeProgress(
            userId: userVM.uid,
            date: challengeDate,
            played: true,
            completed: completed,
            timeRemaining: completed || timerSeconds <= 0 ? nil : timerSeconds,
            timeTakenSeconds: totalTime - timerSeconds,
            riddleResults: riddleResults,
            hintsUsed: hintsUsed,
            revealedHintIndices: Dictionary(uniqueKeysWithValues: viewModel.timerRiddles.indices.map { ($0, Array(showingHintIndices[$0] ?? [])) }),
            attempts: attempts
        )
        guard saved != nil else {
            timer?.invalidate()
            isTimerRunning = false
            saveError = "Your progress couldn't be saved. The timer is paused. Check your connection and retry."
            return false
        }
        saveError = nil
        if let data = viewModel.timerSavedData { restoreState(from: data) }
        // Optionally update Firestore with medal if completed
        if completed, let medal = medal {
            await userVM.updateTimerChallengeStreak(completedToday: true, date: challengeDate)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            let dateStr = formatter.string(from: challengeDate)
            let progressRef = Firestore.firestore().collection("users").document(userVM.uid).collection("timerDailyChallengeProgress").document(dateStr)
            do {
                try await progressRef.setData(["medal": medal], merge: true)
                print("Saved medal: \(medal) for date \(dateStr)")
            } catch {
                print("Failed to save medal: \(error)")
            }
        }
        return true
    }
    
    @MainActor
    private func loadSavedProgress() async {
        isLoadingProgress = true
        loadError = nil
        defer { isLoadingProgress = false }
        do {
            let data = try await viewModel.loadTimerChallengeProgress(for: userVM.uid, date: challengeDate)
            guard isViewActive else { return }
            userAnswers.removeAll()
            results.removeAll()
            riddleResults.removeAll()
            hintsUsed.removeAll()
            attempts.removeAll()
            showingHintIndices.removeAll()
            hasSavedProgress = data != nil
            if let data {
                restoreState(from: data)
                if data["completed"] as? Bool == true {
                    showGameRecap = true
                } else if timerSeconds == 0 {
                    showGameOver = true
                } else {
                    startTicker()
                }
            } else {
                await viewModel.loadTimerDailyRiddles(date: challengeDate)
                if viewModel.timerRiddles.isEmpty {
                    viewModel.timerRiddles = Array(viewModel.riddles.prefix(3))
                }
                timerSeconds = totalTime
            }
        } catch {
            timer?.invalidate()
            isTimerRunning = false
            loadError = "Couldn't restore your challenge. Check your connection and retry. Your saved game hasn't been replaced."
        }
    }

    private func restoreState(from data: [String: Any]) {
        timerSeconds = GameRules.timerRemainingSeconds(data) ?? timerSeconds
        for (index, riddle) in viewModel.timerRiddles.enumerated() {
            let progress = viewModel.timerProgressCache[riddle.uiId]
            riddleResults[index] = progress?.isCorrect ?? false
            hintsUsed[index] = progress?.usedHints ?? 0
            attempts[index] = progress?.attempts ?? 0
            revealedHints[index] = progress?.revealedHintIndices.count ?? 0
            // Keep visibility separate: loading/saving should not re-open hidden hints.
        }
        if data["completed"] as? Bool == true {
            timer?.invalidate()
            isTimerRunning = false
            if isViewActive { showGameRecap = true }
        } else if timerSeconds == 0 {
            timer?.invalidate()
            isTimerRunning = false
            if isViewActive { showGameOver = true }
        }
    }

    private func determineMedal() -> String? {
        let timeTaken = totalTime - timerSeconds
        if timeTaken <= 60 { return "Gold" }
        else if timeTaken <= 120 { return "Silver" }
        else { return "Bronze" }
    }
}
