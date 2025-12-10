import Foundation

/// Core reminder data model
struct Reminder: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var description: String
    var dueDate: Date
    var notificationLevel: NotificationLevel
    var isCompleted: Bool
    var createdAt: Date
    var modifiedAt: Date
    var phoneNumber: String?        // Required for Level 5 (phone call)
    var twilioCallSid: String?      // For tracking phone call status
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        dueDate: Date,
        notificationLevel: NotificationLevel = .standard,
        isCompleted: Bool = false,
        phoneNumber: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.dueDate = dueDate
        self.notificationLevel = notificationLevel
        self.isCompleted = isCompleted
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.phoneNumber = phoneNumber
        self.twilioCallSid = nil
    }
    
    /// Check if reminder is overdue
    var isOverdue: Bool {
        !isCompleted && dueDate < Date()
    }
    
    /// Time remaining until due date
    var timeRemaining: TimeInterval {
        dueDate.timeIntervalSinceNow
    }
    
    /// Formatted due date string
    var formattedDueDate: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(dueDate) {
            formatter.dateFormat = "'Today at' h:mm a"
        } else if Calendar.current.isDateInTomorrow(dueDate) {
            formatter.dateFormat = "'Tomorrow at' h:mm a"
        } else {
            formatter.dateFormat = "MMM d 'at' h:mm a"
        }
        return formatter.string(from: dueDate)
    }
}

// MARK: - Sample Data
extension Reminder {
    static let sample = Reminder(
        title: "Team Meeting",
        description: "Weekly standup with the team",
        dueDate: Date().addingTimeInterval(3600),
        notificationLevel: .timeSensitive
    )
    
    static let samples: [Reminder] = [
        Reminder(title: "Take medication", dueDate: Date().addingTimeInterval(1800), notificationLevel: .alarmKit),
        Reminder(title: "Call mom", dueDate: Date().addingTimeInterval(7200), notificationLevel: .standard),
        Reminder(title: "Submit report", dueDate: Date().addingTimeInterval(-3600), notificationLevel: .timeSensitive, isCompleted: true),
    ]
}
