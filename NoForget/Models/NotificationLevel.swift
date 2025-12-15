import Foundation
import SwiftUI

/// Represents the four escalating notification intensity levels
enum NotificationLevel: Int, CaseIterable, Codable, Identifiable {
    case standard = 1           // Standard local notification
    case timeSensitive = 2      // Time-sensitive (bypasses notification summary)
    case liveActivity = 3       // Dynamic Island + Live Activity (coming soon)
    case phoneCall = 5          // Twilio phone call to user
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .standard: return "Standard"
        case .timeSensitive: return "Time Sensitive"
        case .liveActivity: return "Live Activity"
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
        case .phoneCall:
            return "Calls your phone to ensure you don't miss it"
        }
    }
    
    var icon: String {
        switch self {
        case .standard: return "bell"
        case .timeSensitive: return "bell.badge"
        case .liveActivity: return "clock.badge.exclamationmark"
        case .phoneCall: return "phone.fill"
        }
    }
    
    var color: String {
        switch self {
        case .standard: return "blue"
        case .timeSensitive: return "orange"
        case .liveActivity: return "purple"
        case .phoneCall: return "green"
        }
    }
    
    /// SwiftUI Color for this notification level
    var levelColor: Color {
        switch self {
        case .standard: return .blue
        case .timeSensitive: return .orange
        case .liveActivity: return .purple
        case .phoneCall: return .green
        }
    }
    
    /// Check if this level is available
    /// - Parameter callOnboardingCompleted: Whether phone call onboarding has been completed
    func isAvailable(callOnboardingCompleted: Bool = true) -> Bool {
        switch self {
        case .standard, .timeSensitive:
            return true
        case .liveActivity:
            return false  // Coming soon
        case .phoneCall:
            return callOnboardingCompleted
        }
    }
}
