import Foundation

/// Represents the five escalating notification intensity levels
enum NotificationLevel: Int, CaseIterable, Codable, Identifiable {
    case standard = 1           // Standard local notification
    case timeSensitive = 2      // Time-sensitive (bypasses notification summary)
    case liveActivity = 3       // Dynamic Island + Live Activity
    case alarmKit = 4           // AlarmKit alarm (iOS 26+, currently disabled)
    case phoneCall = 5          // Twilio phone call to user
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .standard: return "Standard"
        case .timeSensitive: return "Time Sensitive"
        case .liveActivity: return "Live Activity"
        case .alarmKit: return "Alarm"
        case .phoneCall: return "Phone Call"
        }
    }
    
    var description: String {
        switch self {
        case .standard:
            return "Regular notification that appears in Notification Center"
        case .timeSensitive:
            return "Breaks through Focus modes and notification summary"
        case .liveActivity:
            return "Shows countdown in Dynamic Island until reminder time"
        case .alarmKit:
            return "System alarm (coming soon - falls back to Time Sensitive)"
        case .phoneCall:
            return "Calls your phone to ensure you don't miss it"
        }
    }
    
    var icon: String {
        switch self {
        case .standard: return "bell"
        case .timeSensitive: return "bell.badge"
        case .liveActivity: return "clock.badge.exclamationmark"
        case .alarmKit: return "alarm"
        case .phoneCall: return "phone.fill"
        }
    }
    
    var color: String {
        switch self {
        case .standard: return "blue"
        case .timeSensitive: return "orange"
        case .liveActivity: return "purple"
        case .alarmKit: return "red"
        case .phoneCall: return "green"
        }
    }
    
    /// Check if this level is available on the current device
    var isAvailable: Bool {
        switch self {
        case .standard, .timeSensitive:
            return true
        case .liveActivity:
            if #available(iOS 16.1, *) {
                return true
            }
            return false
        case .alarmKit:
            return false  // Disabled until AlarmKit API is finalized
        case .phoneCall:
            return true  // Available if backend is configured
        }
    }
}
