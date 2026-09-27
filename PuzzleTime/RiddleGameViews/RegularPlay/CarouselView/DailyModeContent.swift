//
//  DailyModeContent.swift
//  PuzzleTime
//
//  Created by Peyton White on 12/27/25.
//

import SwiftUI

struct DailyModeContent: View {
    @ObservedObject var vm: CarouselViewModel
    let userVM: UserViewModel

    var body: some View {
        if let daily = vm.viewModel.dailyRiddle {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("Daily Challenge")
                        .font(.headline.bold())
                        .foregroundColor(.orange)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(vm.formattedDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Streak: \(userVM.dailyChallengeStreak) 🔥")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)

                RiddleContent(
                    riddle: daily,
                    progress: vm.viewModel.dailyProgressCache[daily.uiId],
                    userAnswer: $vm.userAnswer,
                    result: $vm.result,
                    isLoading: $vm.isLoading,
                    revealedHints: $vm.revealedHints,
                    pandaWave: $vm.pandaWave,
                    viewModel: vm.viewModel,
                    showingHintIndices: $vm.showingHintIndices,
                    isTransitioning: $vm.isTransitioning,
                    isDailyMode: vm.isDailyMode,
                    isTimerChallenge: false,
                    riddleIndex: 0,
                    onSubmit: { usedHints in
                        vm.submit(riddle: daily, usedHints: usedHints, userVM: userVM)
                    },
                    isAdLoading: $vm.isAdLoading,
                    lastAnsweredRiddleId: $vm.lastAnsweredRiddleId
                )
                .padding(.horizontal, 8)

                Spacer()
            }
        } else {
            Text("Loading daily puzzle...")
                .padding()
        }
    }
}

struct RegularModeContent: View {
    @ObservedObject var vm: CarouselViewModel
    let userVM: UserViewModel

    var body: some View {
        VStack(spacing: 0) {
            CarouselTabView(vm: vm, userVM: userVM)
            PageDotsView(vm: vm)
        }
    }
}
