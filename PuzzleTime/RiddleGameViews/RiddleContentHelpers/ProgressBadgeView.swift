//
//  ProgressBadgeView.swift
//  PuzzleTime
//
//  Created by Peyton White on 11/4/25.
//

import SwiftUI

// MARK: - Progress Badge View
struct ProgressBadgeView: View {
    let progress: RiddleProgress?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if let progress = progress {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if progress.isCorrect {
                        HStack {
                            Label("Solved", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            if let solvedDate = progress.solvedDate {
                                Text("on \(formattedDate(solvedDate))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Label("Not Solved", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                    Text("\(progress.attempts) attempt\(progress.attempts == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(progress.usedHints) hint\(progress.usedHints == 1 ? "" : "s") used")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Last seen: \(formattedDate(progress.lastSeen))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        } else {
            Spacer(minLength: 20)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
