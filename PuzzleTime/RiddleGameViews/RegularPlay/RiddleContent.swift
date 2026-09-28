import SwiftUI
import UIKit // Required for UIActivityViewController

struct RiddleContent: View {
    let riddle: Riddle
    let progress: Any? // Changed to Any to support both RiddleProgress and TimerChallengeProgress
    @Binding var userAnswer: String
    @Binding var result: String
    @Binding var isLoading: Bool
    @Binding var revealedHints: Int
    @Binding var pandaWave: Bool
    @State private var showReport = false
    @State private var showHintConfirmation: Bool = false
    @State private var pendingHintIndex: Int = 0
    @EnvironmentObject var userVM: UserViewModel
    @ObservedObject var viewModel: RiddleViewModel
    @Binding var showingHintIndices: Set<Int>
    @State private var autoHideTasks: [Int: Task<Void, Never>] = [:]
    @State private var usedHintsCount: Int = 0
    @Environment(\.colorScheme) var colorScheme
    @State private var hintCoinPop: Int = 0
    @State private var isSharing: Bool = false
    @Binding var isTransitioning: Bool
    let isDailyMode: Bool // NEW
    let isTimerChallenge: Bool // NEW
    let riddleIndex: Int? // NEW
    let onSubmit: (Int) -> Void
    @Binding var isAdLoading: Bool
    @Binding var lastAnsweredRiddleId: String

    
    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    HStack {
                        if riddle.isNew() { Label("New", systemImage: "sparkles").foregroundStyle(.cyan) }
                        if let label = riddle.difficultyLabel { Text(label).foregroundStyle(.secondary) }
                        Spacer()
                        Button { showReport = true } label: { Image(systemName: "flag") }
                            .accessibilityLabel("Report puzzle")
                            .disabled(isLoading || isAdLoading)
                    }.font(.subheadline)
                    ProgressBadgeView(progress: progress as? RiddleProgress)
                    CoreContentView(
                        riddle: riddle,
                        userAnswer: $userAnswer,
                        result: $result,
                        isLoading: $isLoading,
                        isAdLoading: $isAdLoading,
                        revealedHints: $revealedHints,
                        showingHintIndices: $showingHintIndices,
                        userVM: userVM,
                        viewModel: viewModel,
                        progress: progress,
                        hintCoinPop: $hintCoinPop,
                        usedHintsCount: $usedHintsCount,
                        onSubmit: onSubmit,
                        proxy: proxy,
                        isTransitioning:$isTransitioning,
                        isDailyMode: isDailyMode, // NEW
                        isTimerChallenge: isTimerChallenge,
                        riddleIndex: riddleIndex,
                    )
                    ResultDisplay(
                        result: result,
                        explanation: riddle.explanation,
                        currentRiddleId: riddle.uiId,
                        lastAnsweredRiddleId: $lastAnsweredRiddleId  // ← Pass binding
                    )
                    Spacer(minLength: 75)
                }
                .padding(.horizontal)
            }
            .overlay(HintCoinOverlay(hintCoinPop: hintCoinPop))
        }
        .onChange(of: showReport) { reporting in
            if isTimerChallenge {
                if reporting { viewModel.pauseTimer() } else { viewModel.resumeTimer() }
            }
        }
        .sheet(isPresented: $showReport) {
            PuzzleReportView(riddle: riddle, attemptedAnswer: userAnswer)
        }
        .onAppear {
            if isTimerChallenge {
                if let progress = progress as? TimerChallengeProgress {
                    showingHintIndices = Set(progress.revealedHintIndices)
                    revealedHints = progress.revealedHintIndices.count
                } else {
                    showingHintIndices = []
                    revealedHints = 0
                }
            } else {
                if let progress = progress as? RiddleProgress {
                    showingHintIndices = Set(progress.revealedHintIndices)
                    revealedHints = progress.revealedHintIndices.count
                } else {
                    showingHintIndices = []
                    revealedHints = 0
                }
            }
        }
        .onDisappear {
            cancelAllAutoHides()
        }
    }
    
    private func cancelAllAutoHides() {
        autoHideTasks.values.forEach { $0.cancel() }
        autoHideTasks.removeAll()
    }
}



// MARK: - Core Content View
private struct CoreContentView: View {
    let riddle: Riddle
    @Binding var userAnswer: String
    @Binding var result: String
    @Binding var isLoading: Bool
    @Binding var isAdLoading: Bool
    @Binding var revealedHints: Int
    @Binding var showingHintIndices: Set<Int>
    let userVM: UserViewModel
    let viewModel: RiddleViewModel
    let progress: Any?
    @Binding var hintCoinPop: Int
    @Binding var usedHintsCount: Int
    let onSubmit: (Int) -> Void
    let proxy: GeometryProxy
    @Binding var isTransitioning: Bool
    let isDailyMode: Bool // NEW
    let isTimerChallenge: Bool
    let riddleIndex: Int? // NEW
    
    @Environment(\.colorScheme) var colorScheme
    @State private var autoHideTasks: [Int: Task<Void, Never>] = [:]
    @State private var isSharing: Bool = false

    private var accentColor: Color { colorScheme == .dark ? .pink : .purple }
    
    var body: some View {
        VStack(spacing: 16) {
            RiddleImageSection(
                riddle: riddle,
                isSharing: $isSharing,
                accentColor: accentColor
            )
            
            HintSectionView(
                revealedHints: $revealedHints,
                hints: riddle.hints,
                showingHintIndices: $showingHintIndices,
                autoHideTasks: $autoHideTasks,
                userVM: userVM,
                viewModel: viewModel,
                riddle: riddle,
                progress: progress,
                hintCoinPop: $hintCoinPop,
                isTransitioning: $isTransitioning,
                isDailyMode: isDailyMode,
                isTimerChallenge: isTimerChallenge,
                riddleIndex: riddleIndex,
                isAdLoading: $isAdLoading
            )
            .zIndex(10)
            .disabled(isTransitioning || isLoading)
            .onChange(of: revealedHints) { newValue in
                if newValue > usedHintsCount {
                    usedHintsCount = newValue
                }
            }
            
            if getIfSolved() {
                SolvedButton()
            } else {
                AnswerInput(userAnswer: $userAnswer, result: $result)
            }
            
            SubmitOrAnswerView(
                isDailyChallengeSolved: isDailyChallengeSolvedToday,
                riddle: riddle,
                isLoading: $isLoading,
                userAnswer: userAnswer,
                onSubmit: { onSubmit(usedHintsCount) },
                accentColor: accentColor
            )
            .padding(.top, 20)     // extra space before submit button
            .padding(.bottom, 40)  // crucial: forces scrollable space!
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(.easeInOut(duration: 0.4), value: isTransitioning)
    }
    
    // Extract offset calculation to a function
    private func calculatedOffset(proxy: GeometryProxy) -> CGFloat {
        (proxy.size.height - 280 - 100 - 80 - 100) / 2 - 50
    }
    
    private func getIfSolved() -> Bool {
        if(isDailyMode) {
            return isDailyChallengeSolvedToday
        } else if(isTimerChallenge) {
            return viewModel.timerProgressCache[riddle.uiId]?.isCorrect ?? false
        } else {
            return isDailyChallengeSolvedToday
        }
        
    }
    
    // Extracted daily challenge logic
    private var isDailyChallengeSolvedToday: Bool {
            if isTimerChallenge {
                // Timer challenge uses its own progress
                if let progress = progress as? TimerChallengeProgress {
                    return progress.isCorrect
                }
                return false
            } else if isDailyMode {
                // This progress was loaded from the challenge's dated document.
                // A solve after UTC midnight still belongs to that challenge.
                return (progress as? RiddleProgress)?.isCorrect ?? false
            } else {
                return (progress as? RiddleProgress)?.isCorrect ?? false
            }
        }
}


// MARK: - Riddle Image Section
private struct RiddleImageSection: View {
    let riddle: Riddle
    @Binding var isSharing: Bool
    let accentColor: Color
    
    var body: some View {
        RiddleImageWithShareButton(
            riddle: riddle,
            isSharing: $isSharing,
            accentColor: accentColor
        )
    }
}

// MARK: - Hint Section View
private struct HintSectionView: View {
    @Binding var revealedHints: Int
    let hints: [String] // Assume hints is an array of strings; adjust as needed
    @Binding var showingHintIndices: Set<Int>
    @Binding var autoHideTasks: [Int: Task<Void, Never>]
    let userVM: UserViewModel
    let viewModel: RiddleViewModel
    let riddle: Riddle
    let progress: Any?
    @Binding var hintCoinPop: Int
    @Binding var isTransitioning: Bool
    let isDailyMode: Bool // NEW: To set isDaily correctly
    let isTimerChallenge: Bool
    let riddleIndex: Int? // NEW
    @Binding var isAdLoading: Bool

    var body: some View {
        HintSection(
            revealedHints: $revealedHints,
            hints: hints,
            showingHintIndices: $showingHintIndices,
            autoHideTasks: $autoHideTasks,
            userVM: userVM,
            viewModel: viewModel,
            riddle: riddle,
            progress: progress,
            hintCoinPop: $hintCoinPop,
            isTransitioning: $isTransitioning,
            isDailyMode: isDailyMode,
            isTimerChallenge: isTimerChallenge,
            riddleIndex: riddleIndex,
            isAdLoading: $isAdLoading
        )
    }
}

// MARK: - Submit or Answer View
private struct SubmitOrAnswerView: View {
    let isDailyChallengeSolved: Bool
    let riddle: Riddle
    @Binding var isLoading: Bool
    let userAnswer: String
    let onSubmit: () -> Void
    let accentColor: Color
    
    var body: some View {
        if isDailyChallengeSolved {
            Text("Answer: \(riddle.answer)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(accentColor)
                        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
                )
                .padding(.horizontal, 20)
        } else {
            SubmitButton(
                isLoading: $isLoading,
                userAnswer: userAnswer,
                onSubmit: onSubmit
            )
        }
    }
}




// MARK: - Riddle Image with Share Button
private struct RiddleImageWithShareButton: View {
    let riddle: Riddle
    @Binding var isSharing: Bool
    let accentColor: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            RiddleImage(riddle: riddle)
            HStack {
                Spacer()
                Button(action: {
                    isSharing = true
                    shareRiddleImage()
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                        .foregroundColor(accentColor)
                        .frame(width: 40, height: 40) // Fixed size for centering
                        .background(
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 40, height: 40) // Match circle size
                        )
                }
                .disabled(isSharing)
                .padding(.trailing, 10)
                .accessibilityLabel("Share riddle image")
            }
        }
    }
    
    private func shareRiddleImage() {
        guard let url = URL(string: riddle.photoUrl) else {
            print("Invalid photo URL")
            isSharing = false
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else {
                    print("Failed to convert data to UIImage")
                    isSharing = false
                    return
                }
                
                let activityController = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                
                await MainActor.run {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootViewController = windowScene.windows.first?.rootViewController {
                        if let popover = activityController.popoverPresentationController {
                            popover.sourceView = rootViewController.view
                            popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX,
                                                       y: rootViewController.view.bounds.midY,
                                                       width: 0, height: 0)
                            popover.permittedArrowDirections = []
                        }
                        rootViewController.present(activityController, animated: true) {
                            isSharing = false
                        }
                    } else {
                        print("Unable to find root view controller")
                        isSharing = false
                    }
                }
            } catch {
                print("Failed to download image: \(error)")
                isSharing = false
            }
        }
    }
}


struct HintCoinOverlay: View {
    let hintCoinPop: Int
    @State private var isVisible = false // State to drive animation
    
    var body: some View {
        Group {
            if hintCoinPop > 0 {
                Text("-\(hintCoinPop) coins!")
                    .font(.title2).bold()
                    .foregroundColor(.white)
                    .padding(12)
                    .background(
                        LinearGradient(
                            colors: [.red, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .opacity(0.9)
                        .cornerRadius(12)
                        .shadow(color: .red.opacity(0.5), radius: 8, x: 0, y: 4)
                    )
                    .offset(y: -50)
                    .scaleEffect(hintCoinPop > 5 ? 1.2 : 1.0)
                    .rotation3DEffect(
                        .degrees(isVisible ? 0 : 10), // Rotate on Y-axis
                        axis: (x: 0, y: 1, z: 0)
                    )
                    .opacity(isVisible ? 1 : 0)
                    .scaleEffect(isVisible ? 1 : 0.5)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.2),
                        value: isVisible
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity),
                            removal: .scale(scale: 1.2).combined(with: .opacity).combined(with: .move(edge: .top))
                        )
                    )
                    .zIndex(2)
                    .overlay(
                        SparkleEffect()
                            .opacity(hintCoinPop > 5 ? 0.8 : 0.4)
                    )
                    .onAppear {
                        isVisible = true
                    }
                    .onChange(of: hintCoinPop) { _ in
                        isVisible = false // Reset for re-trigger
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isVisible = true
                        }
                    }
            } else if hintCoinPop == -1 { // Ad-based hint
                Text("Hint Unlocked!")
                    .font(.title2).bold()
                    .foregroundColor(.white)
                    .padding(12)
                    .background(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .opacity(0.9)
                        .cornerRadius(12)
                        .shadow(color: .cyan.opacity(0.5), radius: 8, x: 0, y: 4)
                    )
                    .offset(y: -50)
                    .rotation3DEffect(
                        .degrees(isVisible ? 0 : 10),
                        axis: (x: 0, y: 1, z: 0)
                    )
                    .opacity(isVisible ? 1 : 0)
                    .scaleEffect(isVisible ? 1 : 0.5)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.7),
                        value: isVisible
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity),
                            removal: .scale(scale: 1.2).combined(with: .opacity).combined(with: .move(edge: .top))
                        )
                    )
                    .zIndex(2)
                    .overlay(SparkleEffect())
                    .onAppear {
                        isVisible = true
                    }
                    .onChange(of: hintCoinPop) { _ in
                        isVisible = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isVisible = true
                        }
                    }
            }
        }
    }
}

struct CoinPopView: View {
    let coinPop: Int
    @State private var isVisible = false
    
    var body: some View {
        if coinPop > 0 {
            Text("+\(coinPop) coins!")
                .font(.title2).bold()
                .foregroundColor(.white)
                .padding(12)
                .background(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(0.9)
                    .cornerRadius(12)
                    .shadow(color: .yellow.opacity(0.5), radius: 8, x: 0, y: 4)
                )
                .offset(y: -100)
                .scaleEffect(coinPop > 10 ? 1.3 : 1.0)
                .rotation3DEffect(
                    .degrees(isVisible ? 0 : -10),
                    axis: (x: 0, y: 1, z: 0)
                )
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(isVisible ? 1 : 0.5)
                .animation(
                    .spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.2),
                    value: isVisible
                )
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity),
                        removal: .scale(scale: 1.2).combined(with: .opacity).combined(with: .move(edge: .top))
                    )
                )
                .zIndex(1)
                .overlay(
                    SparkleEffect()
                        .opacity(coinPop > 10 ? 0.8 : 0.4)
                )
                .onAppear {
                    isVisible = true
                }
                .onChange(of: coinPop) { _ in
                    isVisible = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isVisible = true
                    }
                }
        }
    }
}

// Reused SparkleEffect from previous code
struct SparkleEffect: View {
    @State private var offset: CGFloat = 0
    
    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 8, height: 8)
            .blur(radius: 2)
            .opacity(0.6)
            .offset(x: offset, y: -offset)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    offset = 10
                }
            }
    }
}
