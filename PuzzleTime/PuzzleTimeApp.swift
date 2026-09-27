//
//  PuzzleTimeApp.swift
//  PuzzleTime
//
//  Created by Peyton White on 10/30/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseAppCheck  // NEW: For App Check
import AppTrackingTransparency
import Combine
import UserNotifications
import GoogleMobileAds  // Make sure this is imported here



class CCAppCheckProviderFactory: NSObject, AppCheckProviderFactory {  // NEW: Custom factory from your example
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        if #available(iOS 14.0, *) {
            print("ℹ️ Using AppAttestProvider for App Check")
            return AppAttestProvider(app: app)
        } else {
            print("ℹ️ Using DeviceCheckProvider for App Check")
            return DeviceCheckProvider(app: app)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // FirebaseApp.configure() moved to init() for App Check setup
        
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ Failed to request notification authorization: \(error.localizedDescription)")
                return
            }
            print("ℹ️ Notification permission granted: \(granted)")
            
            if granted {
                DispatchQueue.main.async {
                    NotificationManager.shared.scheduleNotifications()
                }
            }
        }
        
        // Set the notification center delegate
        UNUserNotificationCenter.current().delegate = self
        //MobileAds.shared.start(completionHandler: nil)

        return true
    }
    
  
    
    // Handle notifications when the app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification taps
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        print("ℹ️ Notification tapped with identifier: \(identifier)")
        
        // Optionally handle navigation (e.g., to daily or timer challenge)
        // For now, just open the app
        completionHandler()
    }
}

@main
struct PuzzleTimeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var userVM = UserViewModel.shared
    @StateObject private var attStatusManager = ATTStatusManager.shared
    @StateObject var rewardedVM = RewardedViewModel.shared

    init() {
        // NEW: Set up App Check provider before Firebase configure
        #if targetEnvironment(simulator)
            print("ℹ️ Using AppCheckDebugProviderFactory for simulator")
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
            #if DEBUG
                AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
            #else
                AppCheck.setAppCheckProviderFactory(CCAppCheckProviderFactory())
            #endif
        #endif
        
        // NEW: Configure Firebase after setting App Check provider
        FirebaseApp.configure()
        
        // NEW: Fetch and log App Check token for debug/production
        #if DEBUG || targetEnvironment(simulator)
            AppCheck.appCheck().token(forcingRefresh: false) { token, error in
                if let error = error {
                    print("❌ Failed to get App Check debug token: \(error.localizedDescription)")
                    print("❌ Full error: \(error)")
                } else if let token = token {
                    print("✅ App Check Debug Token: \(token.token)")
                    print("ℹ️ Add this token to Firebase Console > App Check > Apps > Your App > Manage Debug Tokens")
                }
            }
        #endif
        
        #if !DEBUG && !targetEnvironment(simulator)
            Task {
                do {
                    let token = try await AppCheck.appCheck().token(forcingRefresh: false)
                    print("✅ App Check Production Token: \(token.token)")
                } catch {
                    print("❌ Failed to get App Check production token: \(error.localizedDescription)")
                    print("❌ Full error: \(error)")
                }
            }
        #endif
        
        // Existing: Register default notification preferences
        NotificationPreferences.registerDefaults()
        
        
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if userVM.isLoggedIn {
                    ContentView()
                        .environmentObject(userVM)
                        .environmentObject(attStatusManager)
                        .environmentObject(rewardedVM)
                } else {
                    ProgressView("Signing in...")
                        .onAppear {
                            Task { try? await userVM.signInAnonymously() }
                        }
                }
            }
            .task {
                // Check notification authorization and reschedule if needed
                do {
                    let settings = try await UNUserNotificationCenter.current().notificationSettings()
                    if settings.authorizationStatus == .authorized {
                        NotificationManager.shared.scheduleNotifications()
                    }
                } catch {
                    print("❌ Failed to get notification settings: \(error.localizedDescription)")
                }
            }
            .task {
                // Ensure login
                if !userVM.isLoggedIn {
                    try? await userVM.signInAnonymously()
                }
            }
        }
    }
}
