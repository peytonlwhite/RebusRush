//
//  ContentStateView.swift
//  PuzzleTime
//
//  Created by Peyton White on 12/27/25.
//

import SwiftUI


struct ContentStateView: View {
    @ObservedObject var vm: CarouselViewModel
    let userVM: UserViewModel
    let isDailyMode: Bool

    var body: some View {
        if vm.viewModel.isLoading {
            ProgressView("Loading riddles...")
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
        } else if let error = vm.viewModel.errorMessage {
            VStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(error)
                    .multilineTextAlignment(.center)
                    .padding()
                Button("Retry") { Task { await vm.viewModel.refresh() } }
            }
        } else if isDailyMode {
            DailyModeContent(vm: vm, userVM: userVM)
        } else if vm.filteredRiddles.isEmpty {
            Text(vm.emptyStateMessage)
                .font(.title3)
                .foregroundColor(.cyan)
                .multilineTextAlignment(.center)
                .padding()
        } else {
            RegularModeContent(vm: vm, userVM: userVM)
        }
    }
}
