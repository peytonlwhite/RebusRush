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

    let viewModel: RiddleViewModel
    let isDailyMode: Bool
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
        return formatter.string(from: Date())
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
        let input = userAnswer.trimmingCharacters(in: .whitespaces).lowercased()
        guard !input.isEmpty else { return }

        isLoading = true
        result = ""
        lastAnsweredRiddleId = "nil"

        Task {
            do {
                let verdict = try await evaluator.evaluate(userAnswer: input, riddle: riddle)
                let isCorrect = verdict == "correct"
                let attempts = (viewModel.progressCache[riddle.uiId]?.attempts ?? 0) + 1
                let coinsEarned = isCorrect ? max(0, 50 - (attempts - 1) * 10 - usedHints * 10) : 0

                if userVM.isLoggedIn {
                    await viewModel.saveProgress(
                        riddle: riddle,
                        isCorrect: isCorrect,
                        attempts: attempts,
                        usedHints: usedHints,
                        coinsEarned: coinsEarned,
                        userId: userVM.uid,
                        isDaily: isDailyMode && riddle.uiId == viewModel.dailyRiddle?.uiId,
                        revealedHintIndices: Array(showingHintIndices)
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
                    isLoading = false
                    print("Evaluation failed: \(error)")
                }
            }
        }
    }
}
