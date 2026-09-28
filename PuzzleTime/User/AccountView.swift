import SwiftUI
import Combine
import AuthenticationServices
import CryptoKit
import Security
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class AppleAccountController: ObservableObject {
    @Published var busy = false
    @Published var message: String?
    @Published var restoreConfirmation = false
    @Published var deleting = false
    private var nonce: String?
    private var restoreCredential: AuthCredential?

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        message = nil
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            nonce = nil; message = "Couldn't start secure sign-in. Please try again."; return
        }
        let raw = bytes.map { String(format: "%02x", $0) }.joined()
        nonce = raw
        request.nonce = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        // Progress sync does not require a name or email address.
        request.requestedScopes = []
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        guard !busy else { return }
        busy = true
        let users = UserViewModel.shared
        users.isChangingAccount = true
        defer { busy = false; users.isChangingAccount = false; nonce = nil }
        do {
            let authorization = try result.get()
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce, let token = apple.identityToken,
                  let tokenString = String(data: token, encoding: .utf8),
                  let user = Auth.auth().currentUser else {
                throw accountError("Couldn't verify Apple sign-in. Please try again.")
            }
            let credential = OAuthProvider.appleCredential(withIDToken: tokenString,
                                                          rawNonce: nonce, fullName: nil)
            if deleting {
                _ = try await user.reauthenticate(with: credential)
                guard let code = apple.authorizationCode,
                      let codeString = String(data: code, encoding: .utf8) else {
                    throw accountError("Apple didn't provide the authorization needed to delete your account.")
                }
                try await Auth.auth().revokeToken(withAuthorizationCode: codeString)
                _ = try await Functions.functions().httpsCallable("deletePlayerAccount").call()
                try Auth.auth().signOut()
                users.isChangingAccount = false
                try await users.startFreshSession()
            } else {
                guard user.isAnonymous else { return }
                do {
                    let linked = try await user.link(with: credential)
                    try await users.adoptAccount(linked.user)
                    message = "Your progress is now saved with Apple."
                } catch let error as NSError {
                    if error.code == AuthErrorCode.credentialAlreadyInUse.rawValue,
                       let updated = error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential {
                        restoreCredential = updated
                        restoreConfirmation = true
                    } else { throw error }
                }
            }
        } catch {
            if (error as NSError).domain != ASAuthorizationError.errorDomain ||
                (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                message = error.localizedDescription
            }
        }
    }

    func cancelRestore() { restoreCredential = nil }

    func restore() async {
        guard let credential = restoreCredential, !busy else { return }
        busy = true
        let users = UserViewModel.shared
        users.isChangingAccount = true
        defer { busy = false; users.isChangingAccount = false; restoreCredential = nil }
        do {
            let result = try await Auth.auth().signIn(with: credential)
            try await users.adoptAccount(result.user)
        } catch { message = "Couldn't restore your account. Please sign in with Apple again. \(error.localizedDescription)" }
    }

    private func accountError(_ message: String) -> NSError {
        NSError(domain: "RebusRush.Account", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

struct AccountView: View {
    @EnvironmentObject private var users: UserViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var apple = AppleAccountController()
    @State private var confirmDeletion = false

    var body: some View {
        NavigationStack {
            Form {
                if users.currentUser?.isAnonymous != false {
                    Section("Keep your progress") {
                        Text("Connect Apple to save this device's coins, streaks, and puzzle progress and restore them on another iPhone. Playing without an account is still available.")
                        Text("By continuing, you agree to connect your current guest progress to your Apple account.")
                            .font(.footnote).foregroundStyle(.secondary)
                        appleButton
                    }
                } else {
                    Section("Saved with Apple") {
                        Label("Progress sync is connected", systemImage: "checkmark.icloud")
                        Text("On another iPhone, use the same Apple account to restore your progress.")
                    }
                    Section {
                        if apple.deleting {
                            Text("Confirm with Apple to permanently delete your account, coins, progress, and reports.")
                            appleButton
                            Button("Cancel deletion") { apple.deleting = false }
                        } else {
                            Button("Delete account and data", role: .destructive) { confirmDeletion = true }
                        }
                    }
                }
                if apple.busy { ProgressView("Please wait…") }
                if let message = apple.message { Text(message) }
            }
            .disabled(apple.busy)
            .navigationTitle("Your account")
            .toolbar { Button("Done") { dismiss() }.disabled(apple.busy) }
            .alert("Restore saved Apple progress?", isPresented: $apple.restoreConfirmation) {
                Button("Cancel", role: .cancel) { apple.cancelRestore() }
                Button("Restore saved progress") { Task { await apple.restore() } }
            } message: {
                Text("This Apple account already has a saved game. Restoring it replaces the guest session on this device. Your current guest coins and progress will not be merged or available on this device afterward.")
            }
            .alert("Delete your account?", isPresented: $confirmDeletion) {
                Button("Cancel", role: .cancel) { }
                Button("Continue", role: .destructive) { apple.deleting = true }
            } message: { Text("All saved coins, progress, streaks, and reports will be permanently removed. You'll confirm your identity with Apple next.") }
        }
        .interactiveDismissDisabled(apple.busy)
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue, onRequest: apple.prepare) { result in
            Task { await apple.complete(result) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 48)
    }
}
