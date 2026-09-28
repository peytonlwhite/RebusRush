import SwiftUI

struct WeeklyPuzzlesView: View {
    @StateObject private var viewModel: RiddleViewModel

    init(puzzles: [Riddle]) {
        let model = RiddleViewModel()
        model.riddles = puzzles
        model.isLoading = false
        _viewModel = StateObject(wrappedValue: model)
    }

    var body: some View {
        Group {
            if viewModel.riddles.isEmpty {
                ContentUnavailableView("More puzzles soon", systemImage: "sparkles",
                    description: Text("New puzzles arrive each week. Check back soon!"))
            } else {
                RiddleCarouselView(viewModel: viewModel, title: "New this week")
            }
        }
        .navigationTitle("New this week")
    }
}
