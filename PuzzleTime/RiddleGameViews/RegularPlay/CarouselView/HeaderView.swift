//
//  HeaderView.swift
//  PuzzleTime
//
//  Created by Peyton White on 12/27/25.
//

import SwiftUI

struct HeaderView: View {
    @ObservedObject var vm: CarouselViewModel
    let userVM: UserViewModel
    let isDailyMode: Bool
    let colorScheme: ColorScheme

    var body: some View {
        HStack {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundColor(.yellow)
            Text("Coins: \(userVM.coins)")
                .font(.headline)
            Spacer()
            if !isDailyMode {
                Menu {
                    ForEach(CarouselViewModel.RiddleFilter.allCases, id: \.self) { filterOption in
                        Button(action: {
                            vm.filter = filterOption
                            vm.selectedIndex = max(0, min(vm.selectedIndex, vm.filteredRiddles.count - 1))
                            vm.resetForNewRiddle()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                vm.filterScale = 1.1
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                    vm.filterScale = 1.0
                                }
                            }
                            Task {
                                await userVM.savePreferredFilter(vm.filter.rawValue)
                            }
                        }) {
                            Text(filterOption.rawValue)
                        }
                    }
                } label: {
                    HStack {
                        Text(vm.filter.rawValue)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        Capsule()
                            .fill(filterGradient)
                            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
                            .shadow(color: filterGlowColor, radius: 10)
                    )
                    .scaleEffect(vm.filterScale)
                }
                .disabled(vm.isLoading || vm.isAdLoading)
            }
        }
        .padding(.horizontal)
        .padding(.top)
    }

    private var filterGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(colors: [Color(hex: "1E90FF"), Color(hex: "00CED1")], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
    }

    private var filterGlowColor: Color {
        colorScheme == .dark ? .cyan.opacity(0.8) : .blue.opacity(0.6)
    }
}
