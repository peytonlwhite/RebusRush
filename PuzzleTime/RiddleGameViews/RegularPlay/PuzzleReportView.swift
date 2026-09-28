import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct PuzzleReportView: View {
    let riddle: Riddle
    let attemptedAnswer: String
    @Environment(\.dismiss) private var dismiss
    @State private var reason = "answer"
    @State private var details = ""
    @State private var submitting = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("What went wrong?", selection: $reason) {
                    Text("My answer should count").tag("answer")
                    Text("Confusing hint").tag("hint")
                    Text("Image problem").tag("image")
                }
                if !attemptedAnswer.isEmpty {
                    LabeledContent("Your answer", value: String(attemptedAnswer.prefix(200)))
                }
                Section("Details (optional)") {
                    TextEditor(text: $details).frame(minHeight: 100)
                        .onChange(of: details) { details = String(details.prefix(1000)) }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button(submitting ? "Sending…" : "Send report") { Task { await submit() } }
                    .disabled(submitting || sent)
            }
            .navigationTitle("Report puzzle")
            .toolbar { Button("Close") { dismiss() }.disabled(submitting) }
            .alert("Thanks for the report", isPresented: $sent) {
                Button("Done") { dismiss() }
            } message: { Text("We'll review this puzzle. Your progress is unchanged.") }
        }
        .interactiveDismissDisabled(submitting)
    }

    private func submit() async {
        guard let uid = Auth.auth().currentUser?.uid, let id = riddle.id else {
            error = "Please reconnect and try again."; return
        }
        submitting = true; error = nil
        defer { submitting = false }
        do {
            try await Firestore.firestore().collection("puzzleReports").document("\(uid)_\(id)_\(reason)")
                .setData(["userId": uid, "riddleId": id, "reason": reason,
                          "answer": String(attemptedAnswer.prefix(200)), "details": details,
                          "createdAt": FieldValue.serverTimestamp(), "status": "open"])
            sent = true
        } catch {
            self.error = "Couldn't send this report. You may have already reported this issue. Please try later."
        }
    }
}
