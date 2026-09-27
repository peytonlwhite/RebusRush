import SwiftUI

struct GameOverView: View {
    let results: [Int: Bool]
    let hintsUsed: [Int: Int]
    let riddles: [Riddle]
    @EnvironmentObject var userVM: UserViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode
    @Binding var path: NavigationPath // Add path binding
    
    var body: some View {
        DarkModeWrapper {
            ZStack {
                BackgroundGradient()
                
                VStack(spacing: 20) {
                    Text("Time's Up!")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                    
                    Text("You didn't finish in time.")
                        .font(.title3)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(0..<riddles.count, id: \.self) { index in
                            HStack {
                                Text("Riddle \(index + 1):")
                                    .foregroundColor(.white)
                                Image(systemName: results[index] == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(results[index] == true ? .green : .red)
                                Text("Hints: \(hintsUsed[index] ?? 0)")
                                    .foregroundColor(.yellow)
                            }
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(12)
                    
                    Text("Try again tomorrow!")
                        .font(.title3)
                        .foregroundColor(.cyan)
                    
                    Button(action: {
                        path = NavigationPath() // Reset path to clear stack
                    }) {
                        Text("Home")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                            )
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
                .padding(.top)
            }
            .navigationTitle("Game Over")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true) // Hide back button
        }
    }
}
