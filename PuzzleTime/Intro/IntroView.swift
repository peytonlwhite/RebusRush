import SwiftUI
import ConfettiSwiftUI
import FirebaseFirestore
import Combine
import GoogleMobileAds
import UserNotifications // NEW: For notification permissions check
import AppTrackingTransparency


// MARK: - MAIN INTRO
struct IntroView: View {
    @State private var animatePlay = false
    @State private var confettiTrigger: Int = 0
    @State private var pandaPeek: CGFloat = 0
    @Binding var path: NavigationPath
    @StateObject private var viewModel = RiddleViewModel()
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var rewardedVM: RewardedViewModel

    @State private var showResetConfirmation: Bool = false
    @State private var showHowToPlay: Bool = false
    @State private var showContactUsSheet: Bool = false
    @State private var isAdLoading: Bool = false
    @State private var isPandaWaving: Bool = false
    @State private var showAdError: Bool = false
    @State private var showNotificationsSettings: Bool = false // NEW: For notifications sheet
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        DarkModeWrapper {
            ZStack {
                BackgroundGradient()
                
                VStack(spacing: 20) {
                    // Header with coins, ad button, and gear icon
                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(.yellow)
                        
                        Text("Coins: \(formatNumber(userVM.coins))")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.trailing, 5)
                        
                        Button(action: {
                            Task {
                                    await handleAdForCoinsSafely()
                                }
                        }) {
                            HStack {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundColor(.white)
                                Text("Ad for Coins")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                Capsule()
                                    .fill(adGradient)
                                    .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
                                    .shadow(color: adGlowColor, radius: 10)
                            )
                            .opacity(isAdLoading ? 0.6 : 1.0)
                            .overlay(
                                isAdLoading ? ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8) : nil
                            )
                        }
                        .disabled(isAdLoading)
                        
                        Spacer()
                        
                        Menu {
                            Button(action: { showHowToPlay = true }) {
                                Label("How To Play", systemImage: "questionmark.circle")
                            }
                            Button(action: { showContactUsSheet = true }) {
                                Label("Contact Us", systemImage: "envelope.fill")
                            }
                            Button(action: { showResetConfirmation = true }) {
                                Label("Reset Game", systemImage: "arrow.clockwise")
                            }
                            Button(action: { showNotificationsSettings = true }) { // NEW: Notifications button
                                Label("Notifications", systemImage: "bell.fill")
                            }
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.cyan)
                                .font(.title2)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    ContentStack(
                        animatePlay: $animatePlay,
                        onPlay: triggerConfettiAndNavigate,
                        onDaily: triggerDailyChallenge,
                        onTimerChallenge: triggerTimerChallenge,
                        viewModel: viewModel
                    )
                    
                    PandaPeekingBehindPlay(pandaPeek: $pandaPeek, isWaving: $isPandaWaving)
                    
                    if rewardedVM.isBannerAdLoaded, let bannerView = rewardedVM.getBannerView() {
                        BannerAdView(bannerView: bannerView)
                            .frame(width: AdSizeBanner.size.width, height: AdSizeBanner.size.height)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black.opacity(0.2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                    )
                            )
                            .padding(.bottom, 10)
                    } else {
                        Color.clear
                            .frame(height: AdSizeBanner.size.height)
                            .padding(.bottom, 10)
                    }
                }
                
                ConfettiLayer(trigger: $confettiTrigger)
                
                if isAdLoading {
                    ZStack {
                        // Subtle blurred background
                        VisualEffectBlur(blurStyle: .systemMaterialDark)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: .purple.opacity(0.4), radius: 15, x: 0, y: 8)
                            .frame(width: 180, height: 180)
                        
                        VStack(spacing: 12) {
                            // Animated spinning icon with glow
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.yellow)
                                .shadow(color: .yellow.opacity(0.6), radius: 10)
                                .rotationEffect(.degrees(isAdLoading ? 360 : 0))
                                .animation(
                                    .linear(duration: 1.5)
                                    .repeatForever(autoreverses: false),
                                    value: isAdLoading
                                )
                            
                            // Bouncing "Loading Ad..." text
                            Text("Loading Ad...")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .scaleEffect(isAdLoading ? 1.05 : 1.0)
                                .animation(
                                    .easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true),
                                    value: isAdLoading
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
                    .transition(.opacity)
                }
                
            }
        }
        .alert("Ad Unavailable", isPresented: $showAdError) {
            Button("OK") { }
        } message: {
            Text("Unable to load ad. Check your internet or try again later.")
        }
        .alert("Reset Game?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                Task {
                    await userVM.resetGame()
                    await viewModel.clearProgressCache()
                }
            }
        } message: {
            Text("This will reset your coins to 300 and clear all riddle progress. Your daily challenge streak will not be affected. Continue?")
        }
        .navigationDestination(for: String.self) { view in
            if view == "riddle" {
                RiddleCarouselView(viewModel: viewModel, isDailyMode: false)
                    .environmentObject(userVM)
            } else if view == "daily" {
                RiddleCarouselView(viewModel: viewModel, isDailyMode: true)
                    .environmentObject(userVM)
            } else if view == "timerChallenge" {
                TimerChallengeView(viewModel: viewModel, path: $path)
                    .environmentObject(userVM)
            }
        }
        .sheet(isPresented: $showContactUsSheet) {
            ContactUsSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showHowToPlay) {
            HowToPlayView()
        }
        .sheet(isPresented: $showNotificationsSettings) {
            NotificationsSettingsView()
                .presentationDetents([.medium])
        }
        .onChange(of: isAdLoading) { newValue in
            if newValue {
                // Reset rotation if needed
                withAnimation { }
            }
        }
        .onAppear {
            animatePlay = true
            withAnimation(.easeOut(duration: 1.2).delay(0.5)) {
                pandaPeek = 1
            }
            Task {
                try? await userVM.signInAnonymously()
                await userVM.resetTimerChallengeStreakIfNeeded()
                await userVM.loadHasTimerProgress()
                await viewModel.refresh()
                
                // REMOVE this line → try? await ATTStatusManager.shared.requestAuthorization()
                
                await rewardedVM.loadRewardedAd()
                rewardedVM.loadBannerAd()
                
            }
        }
    }

    func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            let value = Double(number) / 1_000_000
            let formatted = String(format: value.truncatingRemainder(dividingBy: 1) == 0 ? "%.0fM" : "%.1fM", value)
            return formatted
        } else if number >= 1000 {
            let value = Double(number) / 1000
            let formatted = String(format: value.truncatingRemainder(dividingBy: 1) == 0 ? "%.0fk" : "%.1fk", value)
            return formatted
        } else {
            return "\(number)"
        }
    }
    
    private func handleAdForCoinsSafely() async {
        // 1. Show loading immediately
        await MainActor.run { isAdLoading = true }
        
        // 2. Request ATT only if still not determined
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            do {
                // This is the only line that can actually throw
                _ = try await ATTStatusManager.shared.requestAuthorization()
                
                // Small breathing room after the native ATT popup disappears
                try await Task.sleep(nanoseconds: 800_000_000) // 0.8 sec
            } catch {
                print("ATT request failed or was cancelled: \(error)")
                // Even if user denies or it fails, we can still try to show non-personalized ads
            }
        }
        
        // 3. Now finally load & show the rewarded ad
        await watchAdForCoins()
        
        // 4. Hide loading spinner (watchAdForCoins already sets it to false on failure too)
        await MainActor.run { isAdLoading = false }
    }
    
    private func watchAdForCoins() async {
        await MainActor.run { isAdLoading = true }

        // 1. Load ad
        let loaded = await rewardedVM.loadRewardedAd()
        
        await MainActor.run {
            viewModel.pauseTimer()
            isAdLoading = false
        }

        guard loaded else {
                print("⚠️ Rewarded ad failed to load")
                // New: Show user feedback
                await MainActor.run {
                    // Assuming you have a @State var showAdError: Bool = false in IntroView, and .alert(isPresented: $showAdError) { ... }
                    showAdError = true
                }
                return
            }

        // 2. Present ad safely on main thread
        await MainActor.run {
            rewardedVM.showAd { reward in
                Task {
                    do {
                        let userRef = Firestore.firestore()
                            .collection("users")
                            .document(userVM.uid)
                        
                        // This works whether the doc exists or not
                        try await userRef.setData([
                            "coins": FieldValue.increment(Int64(reward))
                        ], merge: true)
                        
                        await userVM.refreshCoins()
                        confettiTrigger += 1
                        viewModel.resumeTimer()
                        
                    } catch {
                        print("❌ Failed to grant reward coins: \(error)")
                        // Optionally show a toast to user
                    }
                }
            } onDismiss: {
                viewModel.resumeTimer()
            }
        }
    }

    
    private func triggerTimerChallenge() {
        confettiTrigger += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            path.append("timerChallenge")
        }
    }
    
    private func triggerConfettiAndNavigate() {
        confettiTrigger += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            path.append("riddle")
        }
    }
    
    private func triggerDailyChallenge() {
        confettiTrigger += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            path.append("daily")
        }
    }
    
    private var adGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(hex: "FF4500"), Color(hex: "FFD700")],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [.red, .yellow], startPoint: .leading, endPoint: .trailing)
    }
    
    private var adGlowColor: Color {
        colorScheme == .dark ? .red.opacity(0.8) : .yellow.opacity(0.6)
    }
}

// NEW: Banner Ad View
struct BannerAdView: UIViewControllerRepresentable {
    let bannerView: BannerView
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(bannerView)
        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            bannerView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
            bannerView.widthAnchor.constraint(equalToConstant: AdSizeBanner.size.width),
            bannerView.heightAnchor.constraint(equalToConstant: AdSizeBanner.size.height)
        ])
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - SUB‑VIEWS
struct BackgroundGradient: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(hex: "0F0F1A"), Color(hex: "1A0B2E")]
                : [Color(.systemIndigo).opacity(0.1), Color(.systemPurple).opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// In IntroView.swift, update ContentStack
private struct ContentStack: View {
    @Binding var animatePlay: Bool
    let onPlay: () -> Void
    let onDaily: () -> Void
    let onTimerChallenge: () -> Void
    @EnvironmentObject var userVM: UserViewModel
    @ObservedObject var viewModel: RiddleViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Spacer()
            Spacer()
            Spacer()
            TitleView(animatePlay: animatePlay)
            FloatingBulbs()
            PlayButton(animatePlay: $animatePlay, onTap: onPlay)
            DailyChallengeButton(
                onTap: onDaily,
                isSolved: isDailyChallengeSolved,
                streak: userVM.dailyChallengeStreak,
                showNewBadge: !isDailyChallengeSolved
            )
            TimerChallengeButton(
                onTap: onTimerChallenge,
                isPlayed: userVM.hasTimerChallengeProgress, // Use UserViewModel
                streak: userVM.timerChallengeStreak,
                showNewBadge: !userVM.hasTimerChallengeProgress // Show badge if no progress
            )
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var formattedDate: String {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: today)
    }

    private var isDailyChallengeSolved: Bool {
        guard let lastSolved = userVM.dailyChallengeLastSolved else { return false }
        return Calendar.current.isDate(lastSolved, inSameDayAs: Date())
    }
}

private struct DailyChallengeButton: View {
    let onTap: () -> Void
    let isSolved: Bool
    let streak: Int
    let showNewBadge: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    private var maxButtonWidth: CGFloat {
        horizontalSizeClass == .regular ? 500 : .infinity
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(.white)

                Text("Daily Challenge")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                badgeView

                Spacer()

                Text("Streak: \(streak) 🔥")
                    .font(.caption.bold())
                    .foregroundColor(.yellow)
            }
            .padding(16)
            .frame(maxWidth: maxButtonWidth)
            .background(
                Capsule()
                    .fill(dailyGradient)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    )
                    .shadow(color: glowColor, radius: 15)  // ← FIXED VERSION
            )

        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isSolved)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showNewBadge)
    }

    // MARK: - Badge (Matches Timer Button)
    @ViewBuilder
    private var badgeView: some View {
        if showNewBadge && !isSolved {
            Text("New!")
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    Capsule()
                        .fill(dailyGradient)
                        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
                )
        } else if isSolved {
            Text("Solved")
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    Capsule()
                        .fill(.green)
                        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
                )
        }
    }

    private var dailyGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(hex: "FF6B6B"), Color(hex: "FFA500")],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [.orange, .yellow],
                             startPoint: .leading, endPoint: .trailing)
    }

    private var glowColor: Color {
        colorScheme == .dark ? .orange.opacity(0.8) : .yellow.opacity(0.6)
    }
}


private struct TimerChallengeButton: View {
    let onTap: () -> Void
    let isPlayed: Bool
    let streak: Int
    let showNewBadge: Bool
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var viewModel: RiddleViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @State private var progressData: [String: Any]?
    @State private var isLoading: Bool = true

    private var maxButtonWidth: CGFloat {
        horizontalSizeClass == .regular ? 500 : .infinity
    }

    var body: some View {
        VStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
            } else {
                Button(action: canTap ? onTap : {}) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(.white)

                        Text(buttonText)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        badgeView

                        Spacer()

                        if isPlayed && !isFullySolved {
                            Text("Streak: \(streak) 🔥")
                                .font(.caption.bold())
                                .foregroundColor(.yellow)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: maxButtonWidth)
                    .background(
                        Capsule()
                            .fill(timerGradient)
                            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 2))
                            .shadow(color: glowColor, radius: 15)
                    )
                    .opacity(canTap ? 1 : 0.6)
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isPlayed)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showNewBadge)
            }
        }
        .onAppear {
            Task { await fetchProgressData() }
        }
    }

    // MARK: - Badge View (Identical Style)
    @ViewBuilder
    private var badgeView: some View {
        if showNewBadge && !isFullySolved {
            Text("New!")
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    Capsule()
                        .fill(timerGradient)
                        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
                )
        } else if isFullySolved {
            Text("Solved")
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    Capsule()
                        .fill(.green)
                        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
                )
        }
    }

    // MARK: - Computed Vars (unchanged)
    private var buttonText: String {
        if isFullySolved { "Already Played" }
        if isPlayed { "Resume" }
        return "Timer Challenge"
    }

    private var canTap: Bool {
        if isPlayed,
           let data = progressData,
           data["completed"] as? Bool != true,
           let timeRemaining = data["timeRemaining"] as? Int,
           timeRemaining > 0 {
            return true
        }
        return !isPlayed
    }

    private var isFullySolved: Bool {
        if let data = progressData {
            let isCompleted = data["completed"] as? Bool == true
            let timeRemaining = data["timeRemaining"] as? Int ?? 0
            let allSolved = (data["riddleOneCorrect"] as? Bool ?? false)
                         && (data["riddleTwoCorrect"] as? Bool ?? false)
                         && (data["riddleThreeCorrect"] as? Bool ?? false)
            return isCompleted || timeRemaining <= 0 || allSolved
        }
        return false
    }

    private func fetchProgressData() async {
        isLoading = true
        let ref = Firestore.firestore()
            .collection("users")
            .document(userVM.uid)
            .collection("timerDailyChallengeProgress")
            .document(formattedDate)

        do {
            let doc = try await ref.getDocument()
            progressData = doc.data()
        } catch {
            print("TimerChallengeButton: error = \(error)")
            progressData = nil
        }
        isLoading = false
    }

    private var timerGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(hex: "1E90FF"), Color(hex: "00CED1")],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [.blue, .cyan],
                             startPoint: .leading, endPoint: .trailing)
    }

    private var glowColor: Color {
        colorScheme == .dark ? .cyan.opacity(0.8) : .blue.opacity(0.6)
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .init(secondsFromGMT: 0)
        return f.string(from: Date())
    }
}


// ---- Play Button ---------------------------------------------------
private struct PlayButton: View {
    @Binding var animatePlay: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    private var maxButtonWidth: CGFloat {
        horizontalSizeClass == .regular ? 500 : .infinity  // Keeps iPad layouts clean
    }

    var body: some View {
        Button(action: triggerPlay) {
            Text("PLAY")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.vertical, 24)
                .frame(maxWidth: maxButtonWidth)             // ← FIXED
                .background(
                    Capsule()
                        .fill(buttonGradient)
                        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 3))
                        .shadow(color: glowColor, radius: 20)
                )
                .scaleEffect(animatePlay ? 1.1 : 1.0)
        }
        .frame(maxWidth: .infinity)  // Centers the button on iPad
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: animatePlay)
    }

    private var buttonGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(hex: "FF6B6B"), Color(hex: "4ECDC4"), Color(hex: "45B7D1")],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [.orange, .pink, .purple],
                             startPoint: .leading, endPoint: .trailing)
    }

    private var glowColor: Color { colorScheme == .dark ? .cyan.opacity(0.8) : .purple.opacity(0.6) }

    private func triggerPlay() {
        withAnimation(.spring()) { animatePlay.toggle() }
        onTap()
    }
}


// ---- Title with Daily 10 Tagline -----------------------------------------
private struct TitleView: View {
    let animatePlay: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            // Main Title – RebusRush
            (Text("R")
                .foregroundColor(.orange)
             + Text("ebus")
                .foregroundColor(.primary)
             + Text("R")
                .foregroundColor(.cyan)
             + Text("ush")
                .foregroundColor(.primary))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .shadow(color: .purple.opacity(0.5), radius: 10)
            
            // NEW: Daily 10 Tagline
            Text("New riddles every day!")
                .font(.title3.bold())
                .foregroundColor(.yellow)
                .shadow(color: .yellow.opacity(0.6), radius: 8)
                .scaleEffect(animatePlay ? 1.05 : 1.0)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.6)
                        .delay(0.8),
                    value: animatePlay
                )
                .opacity(animatePlay ? 1 : 0)
                .offset(y: animatePlay ? 0 : 20)
                .animation(.easeOut(duration: 0.9).delay(0.7), value: animatePlay)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 20)
    }
}




// ---- Floating Lightbulbs -------------------------------------------
private struct FloatingBulbs: View {
    @State private var offsets: [CGFloat] = Array(repeating: 0, count: 5)

    var body: some View {
        ZStack {
            ForEach(0..<5) { i in
                Lightbulb(index: i, offset: offsets[i])
            }
        }
        .frame(height: 80)
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                offsets = [-30, -40, -25, -35, -30]
            }
        }
    }
}


private struct Lightbulb: View {
    let index: Int
    let offset: CGFloat
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Image(systemName: "lightbulb.fill")
            .font(.system(size: 30))
            .foregroundColor(bulbColor)
            .offset(y: offset)
            .rotationEffect(.degrees(offset > 0 ? 10 : -10))
    }

    private var bulbColor: Color {
        let light = [Color.yellow, .orange, .pink, .purple, .blue]
        let dark  = [Color.cyan, .pink, .mint, .yellow, .orange]
        return colorScheme == .dark ? dark[index % 5] : light[index % 5]
    }
}


// ---- Panda Peeking Behind Play ------------------------------------
private struct PandaPeekingBehindPlay: View {
    @Binding var pandaPeek: CGFloat
    @Binding var isWaving: Bool
    
    var body: some View {
        GeometryReader { proxy in
            PandaMascotCustom(
                size: proxy.size.width * 0.25,
                isWaving: $isWaving, // Pass binding
                peekOffset: pandaPeek,
                bounce: true
            )
            .position(x: proxy.size.width * 0.85, y: proxy.size.height - 25)
            .onTapGesture {
                withAnimation {
                    isWaving = true // Start waving
                }
                // Reset isWaving after animation (0.5s * 3 repetitions)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isWaving = false
                }
            }
        }
        .ignoresSafeArea()
    }
}


struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}

struct AdLoadingOverlay: View {
    @Binding var isAdLoading: Bool
    @State private var rotationAngle: Double = 0
    @State private var scaleEffect: CGFloat = 1.0
    
    var body: some View {
        if isAdLoading {
            // Stack the background and the loading box together
            ZStack {
                // 1. Full-screen background to capture taps and dim the UI
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                
                // 2. Centered Loading Content Box
                ZStack {
                    // *** FIX APPLIED HERE: Using .dark for compatibility ***
                    VisualEffectBlur(blurStyle: .dark)
                        .frame(width: 160, height: 160)
                        .cornerRadius(25)
                        .shadow(color: .purple.opacity(0.6), radius: 20, x: 0, y: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        )
                    
                    VStack(spacing: 15) {
                        // 3. Animated Icon
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.yellow)
                            .shadow(color: .yellow.opacity(0.8), radius: 12)
                        
                        // 4. Animated Text
                        Text("Loading Ad...")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .scaleEffect(scaleEffect)
                    }
                }
            } // End inner ZStack
            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    rotationAngle = 360
                }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    scaleEffect = 1.05
                }
            }
            .onDisappear {
                rotationAngle = 0
                scaleEffect = 1.0
            }
        } // End if isAdLoading
    }
}
