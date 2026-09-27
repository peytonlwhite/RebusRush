//
//  ContactUsView.swift
//  PuzzleTime
//
//  Created by Peyton White on 11/14/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth


struct ContactUsSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage = ""
    @State private var isVisible = false // For animation

    private let db = Firestore.firestore()

    var body: some View {
        ZStack {
            // Background with gradient
            LinearGradient(
                colors: [.black, .gray.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                Text("Contact Us")
                    .font(.title).bold()
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .overlay(SparkleEffect().offset(x: 100, y: -20))

                // Form
                VStack(spacing: 15) {
                    // Name Field
                    TextField("Name", text: $name)
                        .font(.headline)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ), lineWidth: 2)
                        )
                        .shadow(color: .yellow.opacity(0.3), radius: 5)

                    // Email Field
                    TextField("Email", text: $email)
                        .font(.headline)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ), lineWidth: 2)
                        )
                        .shadow(color: .cyan.opacity(0.3), radius: 5)

                    // Message Field
                    TextEditor(text: $message)
                        .font(.headline)
                        .padding()
                        .frame(height: 120)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(LinearGradient(
                                    colors: [.red, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ), lineWidth: 2)
                        )
                        .shadow(color: .red.opacity(0.3), radius: 5)
                }
                .padding(.horizontal)

                // Error Message
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                // Submit Button
                Button(action: submitForm) {
                    Text(isSubmitting ? "Submitting..." : "Send Message")
                        .font(.headline).bold()
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .shadow(color: .yellow.opacity(0.5), radius: 8)
                }
                .disabled(isSubmitting || name.isEmpty || email.isEmpty || message.isEmpty)
                .padding(.horizontal)
                .scaleEffect(isSubmitting ? 0.95 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSubmitting)

                // Success Pop-up
                if showSuccess {
                    Text("Message Sent!")
                        .font(.title2).bold()
                        .foregroundColor(.white)
                        .padding(12)
                        .background(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .opacity(0.9)
                            .cornerRadius(12)
                            .shadow(color: .cyan.opacity(0.5), radius: 8)
                        )
                        .offset(y: -50)
                        .scaleEffect(isVisible ? 1.0 : 0.5)
                        .opacity(isVisible ? 1 : 0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isVisible)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity),
                                removal: .scale(scale: 1.2).combined(with: .move(edge: .top))
                            )
                        )
                        .overlay(SparkleEffect())
                        .zIndex(2)
                        .onAppear {
                            isVisible = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showSuccess = false
                                dismiss()
                            }
                        }
                }

                Spacer()
            }
            .padding(.vertical)
            .scaleEffect(isVisible ? 1.0 : 0.8)
            .opacity(isVisible ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isVisible)
            .onAppear {
                isVisible = true
            }
        }
    }

    private func submitForm() {

        // Basic validation
        guard !name.isEmpty, !email.isEmpty, !message.isEmpty else {
            errorMessage = "Please fill in all fields."
            return
        }
        guard email.contains("@") else {
            errorMessage = "Please enter a valid email."
            return
        }

        isSubmitting = true
        errorMessage = ""

        
        // Firestore submission
        let data: [String: Any] = [
            "userId": Auth.auth().currentUser?.uid ?? "NOT LOGGED IN",
            "name": name,
            "email": email,
            "message": message,
            "timestamp": FieldValue.serverTimestamp()
        ]

        db.collection("contactUs").addDocument(data: data) { error in
            DispatchQueue.main.async {
                isSubmitting = false
                if let error = error {
                    errorMessage = "Failed to send: \(error.localizedDescription)"
                } else {
                    showSuccess = true
                    name = ""
                    email = ""
                    message = ""
                }
            }
        }
    }
}

