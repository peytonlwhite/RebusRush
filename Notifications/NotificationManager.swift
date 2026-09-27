import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    func scheduleNotifications() {
        // Remove existing notifications to avoid duplicates
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // Schedule notifications based on user preferences
        if NotificationPreferences.dailyNotificationsEnabled {
            scheduleDailyChallengeNotification()
        }
        if NotificationPreferences.timerNotificationsEnabled {
            scheduleTimerChallengeNotification()
        }
        if NotificationPreferences.generalPromptNotificationsEnabled {
            scheduleGeneralPromptNotification()
        }
    }
    
    func rescheduleNotifications() {
        // Reschedule notifications to reflect current preferences
        scheduleNotifications()
    }
    
    private func scheduleDailyChallengeNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Daily Challenge Awaits!"
        content.body = "Your daily puzzle is ready! 🧩 Solve it now!"
        content.sound = .default
        content.badge = 1
        
        var dateComponents = DateComponents()
        dateComponents.hour = 9 //9am
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(identifier: "dailyChallenge", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule daily challenge notification: \(error.localizedDescription)")
            } else {
                print("ℹ️ Scheduled daily challenge notification")
            }
        }
    }
    
    private func scheduleTimerChallengeNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Timer Challenge Time!"
        content.body = "Time’s ticking! ⏰ Try the Timer Challenge!"
        content.sound = .default
        content.badge = 1
        
        var dateComponents = DateComponents()
        dateComponents.hour = 12 // 12 PM
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(identifier: "timerChallenge", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule timer challenge notification: \(error.localizedDescription)")
            } else {
                print("ℹ️ Scheduled timer challenge notification")
            }
        }
    }
    
    private func scheduleGeneralPromptNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Got Time to Waste?"
        content.body = "Solve me! 😜 New puzzles are waiting!"
        content.sound = .default
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 259200, repeats: true) // 3 days
        
        let request = UNNotificationRequest(identifier: "generalPrompt_\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule general prompt notification: \(error.localizedDescription)")
            } else {
                print("ℹ️ Scheduled general prompt notification")
            }
        }
    }
}
