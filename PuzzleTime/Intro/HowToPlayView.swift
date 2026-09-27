import SwiftUI

// MARK: - How to Play View
struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss // NEW: Environment dismiss action
    
    var body: some View {
        DarkModeWrapper {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("How to Play Rebus Puzzles")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                            .padding(.bottom, 5)

                        // Overview
                        Text("Overview")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.cyan)
                        Text("""
                            Rebus puzzles are clever brain teasers that use pictures, letters, numbers, or symbols to represent words or phrases. Your goal is to decode the visual or textual clues to figure out the hidden word or phrase and type it into the answer field.

                            In this app, each puzzle presents an image that contains the rebus clues. You may need to combine elements like images, letters, or symbols, and consider their arrangement or wordplay to find the answer. Hints are available to guide you, and you earn coins for solving puzzles—fewer attempts and hints mean more coins!
                            """)
                            .foregroundColor(.white)
                            .lineSpacing(4)

                        // Mechanics
                        Text("Rebus Puzzle Mechanics")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.cyan)
                        Text("""
                            - **Clues**: Each puzzle shows an image with visual elements (e.g., words, symbols, or their arrangement).
                            - **Wordplay**: Combine the elements to form a word or phrase. For example, a word circled at the top of a stack might emphasize its position.
                            - **Positioning**: The placement of elements matters, like words stacked vertically with one highlighted to suggest a specific phrase.
                            - **Gramograms**: Some puzzles use letters or numbers to sound out words, like "CU" for "see you" or "4" for "for."
                            - **Input**: Type the exact word or phrase (e.g., "top secret") into the text field and submit.
                            - **Hints**: Use hints to reveal parts of the solution, but they cost coins or reduce your reward.
                            """)
                            .foregroundColor(.white)
                            .lineSpacing(4)

                        // Example Puzzle
                        Text("Example Puzzle")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.cyan)
                        Text("**Question**: What phrase is shown in the image?")
                            .foregroundColor(.white)
                            .italic()
                        
                        HStack {
                            Spacer()
                            Image("topSecret")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .padding(.vertical, 5)
                            Spacer()
                        }
                       
                        
                        Text("**Image Description**: Three words stacked vertically spelling 'secret,' with the top word circled.")
                            .foregroundColor(.white)
                            .padding(.vertical, 5)
                        Text("""
                            **Hint 1**: Look at the position of the words and the emphasis on the top one.
                            **Hint 2**: The circled word at the top suggests it’s the key part of the phrase, combined with the word below.
                            **Answer**: top secret

                            In the app, you’d see this image, type "top secret" into the answer field, and submit. If correct, you’d earn coins and see a fun confetti animation!
                            """)
                            .foregroundColor(.white)
                            .lineSpacing(4)

                        // Tips
                        Text("Tips")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.cyan)
                        Text("""
                            - Pay attention to the arrangement of elements, like which part is highlighted or positioned differently.
                            - Use hints sparingly to maximize your coin rewards.
                            - In Daily Mode, solve the daily challenge to build your streak and earn extra coins.
                            - In regular mode, filter puzzles to focus on unsolved ones for more challenges.
                            - Share puzzle images with friends to see if they can solve them too!
                            """)
                            .foregroundColor(.white)
                            .lineSpacing(4)

                        Spacer()
                    }
                    .padding()
                }
                .background(
                    LinearGradient(
                        colors: [Color(hex: "1A1A2E"), Color(hex: "16213E")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                )
                .navigationTitle("How to Play")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss() // NEW: Use dismiss action
                        }
                    }
                }
            }
        }
    }
}
