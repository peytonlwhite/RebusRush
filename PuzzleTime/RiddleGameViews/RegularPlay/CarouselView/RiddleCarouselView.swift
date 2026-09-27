import SwiftUI
import FirebaseAILogic
import ConfettiSwiftUI
import GoogleMobileAds
import Combine


// MARK: - MAIN CAROUSEL VIEW
struct RiddleCarouselView: View {
    @StateObject private var vm: CarouselViewModel
    @EnvironmentObject var adVM: RewardedViewModel
    @EnvironmentObject var userVM: UserViewModel
    @Environment(\.colorScheme) var colorScheme

    init(viewModel: RiddleViewModel, isDailyMode: Bool = false) {
        _vm = StateObject(wrappedValue: CarouselViewModel(viewModel: viewModel, isDailyMode: isDailyMode))
    }

    var body: some View {
        DarkModeWrapper {
            ZStack {
                BackgroundGradientCarouselView()

                PandaBehindImage(pandaPeek: $vm.pandaPeek, isWaving: $vm.pandaWave)

                VStack {
                    HeaderView(vm: vm, userVM: userVM, isDailyMode: vm.isDailyMode, colorScheme: colorScheme)

                    ContentStateView(vm: vm, userVM: userVM, isDailyMode: vm.isDailyMode)

                    Spacer()
                }

                if vm.coinPop > 0 {
                    CoinPopView(coinPop: vm.coinPop)
                }

                ConfettiLayer(trigger: $vm.confettiTrigger)

                AdLoadingOverlay(isAdLoading: $vm.isAdLoading)
            }
            .navigationTitle("Puzzles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { vm.showHowToPlay = true }) {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.cyan)
                            .font(.system(size: 18))
                            .accessibilityLabel("How to play")
                    }
                }
            }
            .sheet(isPresented: $vm.showHowToPlay) {
                HowToPlayView()
            }
            .onChange(of: vm.selectedIndex) { newIndex in
                guard newIndex < vm.carouselItems.count else { return }
                vm.isTransitioning = true

                let currentItem = vm.carouselItems[newIndex]

                if case .riddle(let currentRiddle) = currentItem {
                    let progress = vm.isDailyMode
                        ? vm.viewModel.dailyProgressCache[currentRiddle.uiId]
                        : vm.viewModel.progressCache[currentRiddle.uiId]

                    vm.showingHintIndices = Set(progress?.revealedHintIndices ?? [])
                    vm.revealedHints = progress?.revealedHintIndices.count ?? 0

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            vm.isTransitioning = false
                        }
                    }
                } else {
                    vm.isTransitioning = false
                }
            }
            .onChange(of: vm.filter) {
                withAnimation(.easeInOut(duration: 0.45)) {
                    vm.isTransitioning = false
                    vm.selectedIndex = vm.filteredRiddles.isEmpty ? 0 : min(vm.selectedIndex, vm.filteredRiddles.count - 1)
                    vm.resetForNewRiddle()
                }
            }
            .onChange(of: carouselDependencies) {
                vm.updateCarouselItems(adVM: adVM)
            }
            .onAppear {
                vm.resetForNewRiddle()
                withAnimation(.easeOut(duration: 1.0).delay(0.6)) {
                    vm.pandaPeek = 1
                }
                vm.updateCarouselItems(adVM: adVM)
                Task {
                    if vm.isDailyMode, let daily = vm.viewModel.dailyRiddle {
                        vm.selectedIndex = vm.viewModel.riddles.firstIndex { $0.uiId == daily.uiId } ?? 0
                    }
                    if userVM.isLoggedIn {
                        await vm.viewModel.loadProgress(for: userVM.uid)
                    }
                    if let savedFilter = CarouselViewModel.RiddleFilter(rawValue: userVM.preferredFilter) {
                        vm.filter = savedFilter
                    }
                }
            }
            .onChange(of: userVM.isLoggedIn) { isLoggedIn in
                if isLoggedIn {
                    Task {
                        await vm.viewModel.loadProgress(for: userVM.uid)
                    }
                }
            }
        }
    }

    
    
    private var carouselDependencies: CarouselDependencies {
        CarouselDependencies(riddlesHash: vm.filteredRiddles.hashValue, adCount: adVM.nativeAds.count)
    }
}

// MARK: - Extracted Subviews
struct CarouselTabView: View {
    @ObservedObject var vm: CarouselViewModel
    let userVM: UserViewModel
    @EnvironmentObject var adVM: RewardedViewModel

    var body: some View {
        TabView(selection: $vm.selectedIndex) {
            ForEach(Array(vm.carouselItems.enumerated()), id: \.offset) { index, item in
                Group {
                    switch item {
                    case .riddle(let riddle):
                        RiddleContent(
                            riddle: riddle,
                            progress: vm.isDailyMode ? vm.viewModel.dailyProgressCache[riddle.uiId] : vm.viewModel.progressCache[riddle.uiId],
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
                            riddleIndex: index,
                            onSubmit: { usedHints in
                                vm.submit(riddle: riddle, usedHints: usedHints, userVM: userVM)
                            },
                            isAdLoading: $vm.isAdLoading,
                            lastAnsweredRiddleId: $vm.lastAnsweredRiddleId
                        )
                    case .ad(let nativeAd):
                        GADNativeAdViewRepresentable(nativeAd: nativeAd)
                            .frame(height: 600)
                            .padding()
                            .onAppear {
                                adVM.ensureAdsAreLoaded()
                            }
                            .onDisappear {
                                // Optional: help GC by removing reference once off-screen
                            }
                    }
                }
                .tag(index)
                .padding(.horizontal, 8)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }
}

struct PageDotsView: View {
    @ObservedObject var vm: CarouselViewModel

    var body: some View {
        if !vm.filteredRiddles.isEmpty {
            HStack(spacing: 10) {
                ForEach(vm.filteredRiddles.indices, id: \.self) { riddleIndex in
                    let carouselIndex = vm.carouselItemIndex(forRiddleAt: riddleIndex)
                    let isCurrent = vm.selectedIndex == carouselIndex
                    let isSolved = vm.viewModel.progressCache[vm.filteredRiddles[riddleIndex].uiId]?.isCorrect == true

                    Circle()
                        .fill(vm.dotColor(isSolved: isSolved, isCurrent: isCurrent))
                        .frame(width: isCurrent ? 11 : 9, height: isCurrent ? 11 : 9)
                        .scaleEffect(isCurrent ? 1.25 : 1.0)
                        .overlay(
                            Circle()
                                .stroke(isCurrent ? .cyan : .clear, lineWidth: 2)
                                .scaleEffect(isCurrent ? 1.4 : 1.0)
                                .opacity(isCurrent ? 0.6 : 0)
                        )
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: vm.selectedIndex)
                        .animation(.easeInOut(duration: 0.2), value: isSolved)
                }
            }
            .padding(.vertical, 16)
        }
    }
}
