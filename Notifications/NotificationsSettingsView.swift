import SwiftUI

struct NotificationsSettingsView: View {
    @State private var dailyNotificationsEnabled: Bool = NotificationPreferences.dailyNotificationsEnabled
    @State private var timerNotificationsEnabled: Bool = NotificationPreferences.timerNotificationsEnabled
    @State private var generalPromptNotificationsEnabled: Bool = NotificationPreferences.generalPromptNotificationsEnabled
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Notification Preferences")
                            .font(.system(size: 16, weight: .bold, design: .rounded))) {
                    Toggle(isOn: $dailyNotificationsEnabled) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(.orange)
                            Text("Daily Challenge")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                        }
                    }
                    .onChange(of: dailyNotificationsEnabled) { newValue in
                        NotificationPreferences.dailyNotificationsEnabled = newValue
                    }
                    
                    Toggle(isOn: $timerNotificationsEnabled) {
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(.cyan)
                            Text("Timer Challenge")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                        }
                    }
                    .onChange(of: timerNotificationsEnabled) { newValue in
                        NotificationPreferences.timerNotificationsEnabled = newValue
                    }
                    
                    Toggle(isOn: $generalPromptNotificationsEnabled) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.purple)
                            Text("General Prompts")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                        }
                    }
                    .onChange(of: generalPromptNotificationsEnabled) { newValue in
                        NotificationPreferences.generalPromptNotificationsEnabled = newValue
                    }
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .background(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: "0F0F1A"), Color(hex: "1A0B2E")]
                        : [Color(.systemIndigo).opacity(0.1), Color(.systemPurple).opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
        }
    }
}
