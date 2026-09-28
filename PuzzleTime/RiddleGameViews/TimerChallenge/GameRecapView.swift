import SwiftUI
import ConfettiSwiftUI

struct GameRecapView: View {
    let timeTaken: Int
    let results: [Int: Bool]
    let hintsUsed: [Int: Int]
    let riddles: [Riddle]
    @EnvironmentObject var userVM: UserViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode
    @State private var confettiTrigger: Int = 0
    @State private var isSharing: Bool = false
    @Binding var path: NavigationPath // Add path binding
    
    var body: some View {
        DarkModeWrapper {
            ZStack {
                BackgroundGradient()
                
                VStack(spacing: 20) {
                    Text("Challenge Complete!")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.cyan)
                    
                    Text("Time: \(formatTime(timeTaken))")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    Text("Medal: \(medal ?? "None") 🏅")
                        .font(.title2.bold())
                        .foregroundColor(medalColor)
                    
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
                    
                    Button(action: {
                        isSharing = true
                        shareResults()
                    }) {
                        Text("Share Results")
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
                
                ConfettiLayer(trigger: $confettiTrigger)
            }
            .navigationTitle("Game Recap")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true) // Hide back button
            .onAppear {
                confettiTrigger += 1
            }
        }
    }
    
    private var medal: String? {
        if timeTaken <= 60 { return "Gold" }
        else if timeTaken <= 120 { return "Silver" }
        else { return "Bronze" }
    }
    
    private var medalColor: Color {
        switch medal {
        case "Gold": return .yellow
        case "Silver": return .gray
        case "Bronze": return .orange
        default: return .white
        }
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    private func shareResults() {
        let text = "I got \(medal ?? "No") medal in Timer Challenge! Time: \(formatTime(timeTaken)) 🏅 \(results.values.filter { $0 }.count)/3 correct!"
        let activityController = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            if let popover = activityController.popoverPresentationController {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX,
                                           y: rootViewController.view.bounds.midY,
                                           width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootViewController.present(activityController, animated: true) {
                isSharing = false
            }
        }
    }
}
