import Foundation
import AppTrackingTransparency
import Combine // NEW: Required for ObservableObject and @Published

class ATTStatusManager: ObservableObject {
    static let shared = ATTStatusManager()
    @Published var authorizationStatus: ATTrackingManager.AuthorizationStatus = .notDetermined
    
    private init() {
        if #available(iOS 14, *) {
            authorizationStatus = ATTrackingManager.trackingAuthorizationStatus
            print("ℹ️ Initial ATT Status: \(authorizationStatus.rawValue)")
        }
    }
    
    func requestAuthorization() async throws {
        let status = try await ATTrackingManager.requestTrackingAuthorization()
        await MainActor.run { // Use MainActor to update @Published property
            self.authorizationStatus = status
            NotificationCenter.default.post(name: .attAuthorizationStatusDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let attAuthorizationStatusDidChange = Notification.Name("attAuthorizationStatusDidChange")
}
