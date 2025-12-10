import ActivityKit
import Foundation

/// ActivityKit attributes for Live Activities (Level 3)
struct ReminderAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var timeRemaining: TimeInterval
        var status: ReminderStatus
        
        enum ReminderStatus: String, Codable, Hashable {
            case upcoming = "upcoming"
            case imminent = "imminent"  // Less than 5 minutes
            case overdue = "overdue"
        }
    }
    
    var reminderTitle: String
    var reminderDescription: String
    var dueDate: Date
    var reminderId: UUID
}
