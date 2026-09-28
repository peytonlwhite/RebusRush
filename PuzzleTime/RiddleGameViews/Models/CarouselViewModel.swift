//
//  CarouselViewModel.swift
//  PuzzleTime
//
//  Created by Peyton White on 12/27/25.
//

import SwiftUI
import FirebaseAILogic
import ConfettiSwiftUI
import GoogleMobileAds
import Combine

struct CarouselDependencies: Equatable {
    let riddlesHash: Int
    let adCount: Int
}

// MARK: - Carousel ViewModel
@MainActor
class CarouselViewModel: ObservableObject {
    @Published var selectedIndex: Int = 0
    @Published var userAnswer: String = ""
    @Published var result: String = ""
    @Published var isLoading: Bool = false
    @Published var revealedHints: Int = 0
    @Published var pandaPeek: CGFloat = 0
    @Published var pandaWave: Bool = false
    @Published var confettiTrigger: Int = 0
    @Published var coinPop: Int = 0
    @Published var isTransitioning: Bool = false
    @Published var filter: RiddleFilter = .all
    @Published var showingHintIndices: Set<Int> = []
    @Published var filterScale: CGFloat = 1.0
    @Published var showHowToPlay: Bool = false
    @Published var isAdLoading: Bool = false
    @Published var lastAnsweredRiddleId: String = ""
    @Published var carouselItems: [CarouselItem] = []
    private var submittingRiddleIDs: Set<String> = []
    private var progressSubscription: AnyCancellable?

    let viewModel: RiddleViewModel
    let isDailyMode: Bool
    let challengeDate: Date
    let evaluator = RiddleEvaluator()

    enum RiddleFilter: String, CaseIterable {
        case all = "All"
        case solved = "Solved"
        case unsolved = "Unsolved"
    }

    enum CarouselItem {
        case riddle(Riddle)
        case ad(NativeAd)
    }

    init(viewModel: RiddleViewModel, isDailyMode: Bool) {
        self.viewModel = viewModel
        self.isDailyMode = isDailyMode
        self.challengeDate = viewModel.dailyChallengeDate
        // SwiftUI does not automatically observe a view model nested inside another.
        progressSubscription = viewModel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var filteredRiddles: [Riddle] {
        switch filter {
        case .all: return viewModel.riddles
        case .solved: return viewModel.riddles.filter { viewModel.progressCache[$0.uiId]?.isCorrect == true }
        case .unsolved: return viewModel.riddles.filter { viewModel.progressCache[$0.uiId]?.isCorrect != true }
        }
    }

    var emptyStateMessage: String {
        switch filter {
        case .all: return "No riddles available."
        case .solved: return "No riddles solved yet. Keep puzzling!"
        case .unsolved: return "All riddles solved! You’re a puzzle master!"
        }
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: isDailyMode ? challengeDate : Date())
    }

    var accentColor: Color { .cyan }

    func resetForNewRiddle() {
        userAnswer = ""
        result = ""
        isLoading = false
        pandaWave = false
        showingHintIndices = []
        revealedHints = 0
    }

    func updateCarouselItems(adVM: RewardedViewModel) {
        var items: [CarouselItem] = []
        var usedAdIndex = 0

        for (idx, riddle) in filteredRiddles.enumerated() {
            items.append(.riddle(riddle))

            if (idx + 1) % 2 == 0 && idx < filteredRiddles.count - 1,
               let ad = adVM.getAd(at: usedAdIndex) {
                items.append(.ad(ad))
                usedAdIndex += 1
            }
        }

        carouselItems = items
        selectedIndex = min(max(0, selectedIndex), max(0, items.count - 1))
    }

    func carouselItemIndex(forRiddleAt riddleIndex: Int) -> Int {
        for (idx, item) in carouselItems.enumerated() {
            if case .riddle(let riddle) = item,
               filteredRiddles.firstIndex(of: riddle) == riddleIndex {
                return idx
            }
        }
        return riddleIndex
    }

    func dotColor(isSolved: Bool, isCurrent: Bool) -> Color {
        if isSolved {
            return .green
        } else if isCurrent {
            return accentColor
        } else {
            return Color.secondary.opacity(0.4)
        }
    }

    func submit(riddle: Riddle, usedHints: Int, userVM: UserViewModel) {
        let submittingUID = userVM.uid
        let input = userAnswer.trimmingCharacters(in: .whitespaces).lowercased()
        let progress = isDailyMode ? viewModel.dailyProgressCache[riddle.uiId] : viewModel.progressCache[riddle.uiId]
        guard !input.isEmpty, progress?.isCorrect != true,
              !submittingRiddleIDs.contains(riddle.uiId) else { return }
        submittingRiddleIDs.insert(riddle.uiId)

        isLoading = true
        result = ""
        lastAnsweredRiddleId = "nil"

        Task {
            defer { submittingRiddleIDs.remove(riddle.uiId) }
            do {
                let verdict = try await evaluator.evaluate(userAnswer: input, riddle: riddle)
                guard userVM.uid == submittingUID else { isLoading = false; return }
                let isCorrect = verdict == "correct"
                let latestProgress = isDailyMode ? viewModel.dailyProgressCache[riddle.uiId] : viewModel.progressCache[riddle.uiId]
                let attempts = (latestProgress?.attempts ?? 0) + 1
                let purchasedHints = latestProgress?.revealedHintIndices ?? []
                let hintCount = max(usedHints, purchasedHints.count)
                var coinsEarned = isCorrect ? max(0, 50 - (attempts - 1) * 10 - hintCount * 10) : 0

                if userVM.isLoggedIn {
                    coinsEarned = try await viewModel.saveProgress(
                        riddle: riddle,
                        isCorrect: isCorrect,
                        attempts: attempts,
                        usedHints: hintCount,
                        userId: submittingUID,
                        isDaily: isDailyMode,
                        date: challengeDate,
                        revealedHintIndices: purchasedHints
                    )
                }

                await MainActor.run {
                    result = verdict
                    lastAnsweredRiddleId = riddle.uiId

                    if isCorrect {
                        pandaWave = true
                        confettiTrigger += 1
                        withAnimation(.spring()) {
                            coinPop = coinsEarned
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            self.pandaWave = false
                            self.coinPop = 0
                        }
                        userAnswer = ""
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    result = "error"
                    lastAnsweredRiddleId = riddle.uiId
                    isLoading = false
                    print("Evaluation failed: \(error)")
                }
            }
        }
    }
}
