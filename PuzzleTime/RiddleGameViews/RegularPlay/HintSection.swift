import SwiftUI
import Combine // NEW: For RewardedViewModel
import AppTrackingTransparency



// ---- Hint Section -------------------------------------------------
struct HintSection: View {
    @Binding var revealedHints: Int
    let hints: [String]
    @Binding var showingHintIndices: Set<Int>
    @Binding var autoHideTasks: [Int: Task<Void, Never>]
    @ObservedObject var userVM: UserViewModel
    @ObservedObject var viewModel: RiddleViewModel
    @StateObject private var rewardedVM = RewardedViewModel.shared
    let riddle: Riddle
    let progress: Any?
    @Binding var hintCoinPop: Int
    @State private var showHintConfirmation: Bool = false
    @State private var showAdConfirmation: Bool = false
    @State private var pendingHintIndex: Int = 0
    @State private var errorMessage: String?
    @Binding var isTransitioning: Bool
    let isDailyMode: Bool
    let isTimerChallenge: Bool
    let riddleIndex: Int?
    @Binding var isAdLoading: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("Need a hint? (50 coins)")
                .font(.headline).bold()
                .foregroundColor(.primary)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.vertical, 4)
            }

            HStack(spacing: 16) {
                ForEach(0..<3) { i in
                    hintButton(for: i)
                        .disabled(isTransitioning || isAdLoading)
                        .opacity(isTransitioning || isAdLoading ? 0.6 : 1)
                }
            }
            .padding(.horizontal)
            
        
            
        }
        .padding(.top, 8)
        .onDisappear {
            autoHideTasks.values.forEach { $0.cancel() }
            autoHideTasks.removeAll()
        }
        .alert("Use Hint?", isPresented: $showHintConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Use 50 Coins") {
                Task {
                    // Ensure sufficient coins
                    guard userVM.coins >= 50 else {
                        withAnimation {
                            hintCoinPop = 0
                            errorMessage = "Not enough coins! You have \(userVM.coins) coins."
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            errorMessage = nil
                        }
                        return
                    }

                    // Attempt to purchase hint (includes coin deduction)
                    let success = await viewModel.purchaseHint(
                        riddle: riddle,
                        hintIndex: pendingHintIndex,
                        userId: userVM.uid,
                        isDaily: isDailyMode,
                        isTimerChallenge: isTimerChallenge,
                        coinsDeducted: 50,
                        currentHintIndices: Array(showingHintIndices),
                        riddleIndex: riddleIndex
                    )

                    if success {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                            showingHintIndices.insert(pendingHintIndex)
                            revealedHints = showingHintIndices.count
                            hintCoinPop = 50
                            errorMessage = nil
                        }
                        scheduleAutoHide(for: pendingHintIndex)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(.easeOut(duration: 0.6)) {
                                hintCoinPop = 0
                            }
                        }
                    } else {
                        withAnimation {
                            hintCoinPop = 0
                            errorMessage = "Failed to purchase hint. Try again."
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            errorMessage = nil
                        }
                    }
                }
            }
        } message: {
            Text("Reveal a hint for 50 coins? You have \(userVM.coins) coins.")
        }
        .alert("Not Enough Coins!", isPresented: $showAdConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Watch Ad") {
                requestATTIfNeeded()
                Task {
                    isAdLoading = true
                    // Only hide spinner when ad actually finishes (success or dismiss)
                    let loaded = await rewardedVM.loadRewardedAd()
                    
                    if !loaded {
                        await MainActor.run {
                            isAdLoading = false // Stop loading on failure
                            errorMessage = "Ad unavailable right now. Try again soon!"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                errorMessage = nil
                            }
                        }
                        return // Exit the task if loading failed
                    }
                    
                    if loaded {
                        rewardedVM.showAd { _ in
                            Task {
                                // Attempt to purchase hint (no coins deducted)
                                let success = await viewModel.purchaseHint(
                                    riddle: riddle,
                                    hintIndex: pendingHintIndex,
                                    userId: userVM.uid,
                                    isDaily: isDailyMode,
                                    isTimerChallenge: isTimerChallenge,
                                    coinsDeducted: 0,
                                    currentHintIndices: Array(showingHintIndices),
                                    riddleIndex: riddleIndex
                                )
                                
                                // *** CLEANUP AFTER SUCCESSFUL AD PRESENTATION/REWARD ***
                                await MainActor.run {
                                    isAdLoading = false // Re-enable button
                                }
                                
                                if success {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                        showingHintIndices.insert(pendingHintIndex)
                                        revealedHints = showingHintIndices.count
                                        hintCoinPop = -1 // Indicate ad-based hint
                                        errorMessage = nil
                                    }
                                    scheduleAutoHide(for: pendingHintIndex)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                        withAnimation(.easeOut(duration: 0.6)) {
                                            hintCoinPop = 0
                                        }
                                    }
                                } else {
                                    withAnimation {
                                        hintCoinPop = 0
                                        errorMessage = "Failed to unlock hint. Try again."
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        errorMessage = nil
                                    }
                                }
                            }
                        } onDismiss: {
                            // --- ADD THIS LINE ---
                            Task { await MainActor.run { isAdLoading = false } }
                            // --- END ADDED LINE ---
                            withAnimation {
                                // ... (your existing onDismiss logic)
                                hintCoinPop = 0
                                errorMessage = "Watch the full ad to unlock the hint."
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                errorMessage = nil
                            }
                        }
                    } else {
                        await MainActor.run {
                            isAdLoading = false
                            errorMessage = "Ad unavailable right now. Try again soon!"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                errorMessage = nil
                            }
                        }
                    }
                    
                }
            }
        } message: {
            Text("You need 50 coins to unlock a hint, but you have \(userVM.coins). Watch an ad to get a hint for free?")
        }
    }
    
    private func requestATTIfNeeded() {
        Task {
            if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                try? await ATTStatusManager.shared.requestAuthorization()
            }
        }
    }
    

    @ViewBuilder
    private func hintButton(for index: Int) -> some View {
        let isPurchased = isTimerChallenge
            ? (progress as? TimerChallengeProgress)?.revealedHintIndices.contains(index) ?? false
            : (progress as? RiddleProgress)?.revealedHintIndices.contains(index) ?? false
        let isUnlocked = isPurchased

        HintButton(
            index: index,
            isRevealed: isUnlocked,
            isShowing: showingHintIndices.contains(index),
            hintText: index < hints.count ? hints[index] : "",
            isPurchased: isPurchased,
            onTap: {
                handleHintTap(index: index, isUnlocked: isUnlocked, isPurchased: isPurchased)
            },
            revealedHints: $revealedHints,
            isTransitioning: $isTransitioning
        )
    }

    private func handleHintTap(index: Int, isUnlocked: Bool, isPurchased: Bool) {
        if isUnlocked {
            withAnimation {
                if showingHintIndices.contains(index) {
                    showingHintIndices.remove(index)
                    if let task = autoHideTasks[index] {
                        task.cancel()
                        autoHideTasks.removeValue(forKey: index)
                    }
                } else {
                    showingHintIndices.insert(index)
                    scheduleAutoHide(for: index)
                }
            }
        } else {
            pendingHintIndex = index
            if userVM.coins >= 50 {
                showHintConfirmation = true
            } else {
                showAdConfirmation = true
            }
        }
    }

    private func scheduleAutoHide(for index: Int) {
        autoHideTasks[index]?.cancel()
        autoHideTasks.removeValue(forKey: index)

        let task = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.6)) {
                    showingHintIndices.remove(index)
                }
            }
        }
        autoHideTasks[index] = task
    }
}

// ---- Hint Button ---------------------------------------------------
struct HintButton: View {
    let index: Int
    let isRevealed: Bool
    let isShowing: Bool
    let hintText: String
    let isPurchased: Bool
    let onTap: () -> Void
    @Binding var revealedHints: Int
    @Binding var isTransitioning: Bool
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var sizeClass   // ← NEW: Detect iPad!
    
    // Adaptive font size — iPad = BIG and readable
    private var hintFont: Font {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .title3.bold()        // Big, bold, beautiful on iPad
        } else if sizeClass == .regular {
            return .headline.bold()      // iPhone landscape (Pro Max)
        } else {
            return .caption              // iPhone portrait (your current size)
        }
    }
    
    private var bubbleMaxWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 320 : 130
    }
    
    private var bubbleVerticalOffset: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 80 : 65
    }
    
    var body: some View {
        ZStack {
            Button(action: onTap) {
                Circle()
                    .fill(hintBackground)
                    .overlay(
                        Circle()
                            .stroke(isPurchased ? .blue : hintBorderColor, lineWidth: 3)
                            .shadow(color: hintGlowColor, radius: isRevealed ? 12 : 0)
                    )
                    .frame(width: isPad ? 80 : 60, height: isPad ? 80 : 60)  // Bigger button on iPad
                    .scaleEffect(isRevealed ? 1.15 : 1.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isRevealed)
                    .overlay(
                        Group {
                            if isPurchased {
                                Image(systemName: "lightbulb.fill")
                                    .font(isPad ? .largeTitle : .title2)
                                    .foregroundColor(.yellow)
                            } else {
                                Image(systemName: "lightbulb")
                                    .font(isPad ? .largeTitle : .title2)
                                    .foregroundColor(.gray)
                            }
                        }
                    )
            }
            .buttonStyle(.plain)
            
            // REVEALED HINT BUBBLE — NOW iPad-FRIENDLY
            if isRevealed && isShowing && !isTransitioning {
                Text(hintText)
                    .font(hintFont)                     // ← BIG on iPad!
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(16)
                    .background(hintBubbleBackground)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(hintBorderColor.opacity(0.6), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .frame(maxWidth: bubbleMaxWidth)
                    .offset(y: bubbleVerticalOffset)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .zIndex(isShowing ? 5 : 1)
    }
    
    // Helper
    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    private var hintBackground: Color {
        isRevealed
            ? (colorScheme == .dark ? Color(hex: "16213E") : Color.yellow.opacity(0.2))
            : (colorScheme == .dark ? Color(hex: "1A1A2E") : Color(.systemGray4))
    }
    private var hintBorderColor: Color {
        isRevealed ? (colorScheme == .dark ? .cyan : .orange) : .clear
    }
    private var hintGlowColor: Color {
        isRevealed ? (colorScheme == .dark ? .cyan.opacity(0.8) : .yellow.opacity(0.7)) : .clear
    }
    private var hintIconColor: Color {
        isRevealed ? (colorScheme == .dark ? .cyan : .orange) : (colorScheme == .dark ? .gray : .secondary)
    }
    private var hintBubbleBackground: Color {
        colorScheme == .dark ? Color(hex: "1E1E1E") : Color(.systemBackground).opacity(0.95)
    }
}
