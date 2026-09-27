//
//  NotificationPreferences.swift
//  PuzzleTime
//
//  Created by Peyton White on 11/15/25.
//

import Foundation

struct NotificationPreferences {
    private static let dailyKey = "dailyNotificationsEnabled"
    private static let timerKey = "timerNotificationsEnabled"
    private static let generalKey = "generalPromptNotificationsEnabled"
    
    static var dailyNotificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: dailyKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: dailyKey)
            NotificationManager.shared.rescheduleNotifications()
        }
    }
    
    static var timerNotificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: timerKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: timerKey)
            NotificationManager.shared.rescheduleNotifications()
        }
    }
    
    static var generalPromptNotificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: generalKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: generalKey)
            NotificationManager.shared.rescheduleNotifications()
        }
    }
    
    // Initialize defaults (all enabled by default)
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            dailyKey: true,
            timerKey: true,
            generalKey: true
        ])
    }
}
