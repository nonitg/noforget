import Foundation

/// Placeholder for AlarmKit alarms (Level 4) - iOS 26+
/// Currently disabled - will be implemented when AlarmKit API is stable
@MainActor
class AlarmKitManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var scheduledAlarms: Set<String> = []
    
    /// Check if AlarmKit is available (disabled for now)
    var isAvailable: Bool {
        return false  // Disabled until AlarmKit API is finalized
    }
    
    /// Fallback to time-sensitive notification since AlarmKit is disabled
    func scheduleFallbackNotification(for reminder: Reminder, using notificationManager: NotificationManager) async throws {
        var fallbackReminder = reminder
        fallbackReminder.notificationLevel = .timeSensitive
        try await notificationManager.scheduleNotification(for: fallbackReminder)
    }
}
