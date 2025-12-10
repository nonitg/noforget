import Foundation
import ActivityKit

/// Manages Live Activities for Dynamic Island display (Level 3)
@MainActor
class LiveActivityManager: ObservableObject {
    @Published var activeActivities: [String: String] = [:] // Store activity IDs
    
    /// Check if Live Activities are available
    var isAvailable: Bool {
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }
    
    /// Start a Live Activity for a reminder
    @available(iOS 16.2, *)
    func startActivity(for reminder: Reminder) async throws {
        guard isAvailable else {
            throw LiveActivityError.notAvailable
        }
        
        // End any existing activity for this reminder
        await endActivity(for: reminder)
        
        let attributes = ReminderAttributes(
            reminderTitle: reminder.title,
            reminderDescription: reminder.description,
            dueDate: reminder.dueDate,
            reminderId: reminder.id
        )
        
        let initialState = ReminderAttributes.ContentState(
            timeRemaining: reminder.timeRemaining,
            status: reminder.timeRemaining > 300 ? .upcoming : .imminent
        )
        
        let activityContent = ActivityContent(
            state: initialState,
            staleDate: reminder.dueDate.addingTimeInterval(60)
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: activityContent,
                pushType: nil
            )
            activeActivities[reminder.id.uuidString] = activity.id
            print("Started Live Activity for: \(reminder.title)")
            
            // Start update timer
            startUpdateTimer(for: reminder)
        } catch {
            print("Failed to start Live Activity: \(error)")
            throw LiveActivityError.failedToStart(error)
        }
    }
    
    /// Update a Live Activity with current state
    @available(iOS 16.2, *)
    func updateActivity(for reminder: Reminder) async {
        guard let activityId = activeActivities[reminder.id.uuidString] else { return }
        
        // Find the activity
        let activities = Activity<ReminderAttributes>.activities
        guard let activity = activities.first(where: { $0.id == activityId }) else {
            activeActivities.removeValue(forKey: reminder.id.uuidString)
            return
        }
        
        let timeRemaining = reminder.timeRemaining
        let status: ReminderAttributes.ContentState.ReminderStatus
        
        if timeRemaining <= 0 {
            status = .overdue
        } else if timeRemaining <= 300 {
            status = .imminent
        } else {
            status = .upcoming
        }
        
        let updatedState = ReminderAttributes.ContentState(
            timeRemaining: timeRemaining,
            status: status
        )
        
        let activityContent = ActivityContent(
            state: updatedState,
            staleDate: reminder.dueDate.addingTimeInterval(60)
        )
        
        await activity.update(activityContent)
    }
    
    /// End a Live Activity
    @available(iOS 16.2, *)
    func endActivity(for reminder: Reminder) async {
        guard let activityId = activeActivities[reminder.id.uuidString] else { return }
        
        let activities = Activity<ReminderAttributes>.activities
        guard let activity = activities.first(where: { $0.id == activityId }) else {
            activeActivities.removeValue(forKey: reminder.id.uuidString)
            return
        }
        
        let finalState = ReminderAttributes.ContentState(
            timeRemaining: 0,
            status: .overdue
        )
        
        let finalContent = ActivityContent(
            state: finalState,
            staleDate: nil
        )
        
        await activity.end(finalContent, dismissalPolicy: .immediate)
        activeActivities.removeValue(forKey: reminder.id.uuidString)
        print("Ended Live Activity for reminder: \(reminder.id)")
    }
    
    /// End all Live Activities
    @available(iOS 16.2, *)
    func endAllActivities() async {
        for activity in Activity<ReminderAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activeActivities.removeAll()
        print("Ended all Live Activities")
    }
    
    // MARK: - Private Methods
    
    @available(iOS 16.2, *)
    private func startUpdateTimer(for reminder: Reminder) {
        Task {
            while activeActivities[reminder.id.uuidString] != nil {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // Update every minute
                await updateActivity(for: reminder)
                
                // End activity if overdue for more than 5 minutes
                if reminder.timeRemaining < -300 {
                    await endActivity(for: reminder)
                    break
                }
            }
        }
    }
}

// MARK: - Errors
enum LiveActivityError: LocalizedError {
    case notAvailable
    case failedToStart(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Live Activities are not available on this device"
        case .failedToStart(let error):
            return "Failed to start Live Activity: \(error.localizedDescription)"
        }
    }
}
