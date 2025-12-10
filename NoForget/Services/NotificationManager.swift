import Foundation
import UserNotifications

/// Manages standard and time-sensitive notifications (Levels 1-2)
@MainActor
class NotificationManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    init() {
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    /// Request notification permissions
    func requestAuthorization() async {
        do {
            // Request time-sensitive notifications if available
            var options: UNAuthorizationOptions = [.alert, .sound, .badge]
            
            if #available(iOS 15.0, *) {
                options.insert(.timeSensitive)
            }
            
            let granted = try await notificationCenter.requestAuthorization(options: options)
            isAuthorized = granted
            await checkAuthorizationStatus()
            
            if granted {
                print("Notification permission granted")
            } else {
                print("Notification permission denied")
            }
        } catch {
            print("Notification authorization error: \(error)")
        }
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
    }
    
    /// Schedule a notification for a reminder
    func scheduleNotification(for reminder: Reminder) async throws {
        // Handle all notification types that use local notifications
        guard reminder.notificationLevel == .standard ||
              reminder.notificationLevel == .timeSensitive ||
              reminder.notificationLevel == .alarmKit || // Falls back to time-sensitive
              reminder.notificationLevel == .phoneCall   // Backup notification
        else {
            return
        }
        
        // Check if due date is in the future
        guard reminder.dueDate > Date() else {
            print("Skipping notification for past reminder: \(reminder.title)")
            return
        }
        
        // Cancel any existing notification for this reminder
        await cancelNotification(for: reminder)
        
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.description.isEmpty 
            ? "Reminder due now" 
            : reminder.description
        content.sound = .default
        content.categoryIdentifier = "REMINDER"
        content.userInfo = ["reminderId": reminder.id.uuidString]
        
        // Set interruption level based on notification level
        if #available(iOS 15.0, *) {
            switch reminder.notificationLevel {
            case .timeSensitive, .alarmKit, .phoneCall:
                content.interruptionLevel = .timeSensitive
                content.relevanceScore = 1.0
            default:
                content.interruptionLevel = .active
            }
        }
        
        // Create trigger based on due date
        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminder.dueDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: trigger
        )
        
        do {
            try await notificationCenter.add(request)
            print("Scheduled notification for '\(reminder.title)' at \(reminder.dueDate)")
        } catch {
            print("Failed to schedule notification: \(error)")
            throw error
        }
    }
    
    /// Cancel a scheduled notification
    func cancelNotification(for reminder: Reminder) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminder.id.uuidString])
        print("Cancelled notification for: \(reminder.title)")
    }
    
    /// Cancel all pending notifications
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        print("Cancelled all notifications")
    }
    
    /// Get all pending notification requests
    func getPendingNotifications() async -> [UNNotificationRequest] {
        await notificationCenter.pendingNotificationRequests()
    }
    
    /// Debug: print all pending notifications
    func debugPrintPendingNotifications() async {
        let pending = await getPendingNotifications()
        print("Pending notifications: \(pending.count)")
        for notification in pending {
            print("  - \(notification.identifier): \(notification.content.title)")
        }
    }
}
