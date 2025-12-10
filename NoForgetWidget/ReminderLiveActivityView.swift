import WidgetKit
import SwiftUI

/// Live Activity widget for Dynamic Island and Lock Screen (Level 3)
@available(iOS 16.1, *)
struct ReminderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReminderAttributes.self) { context in
            // Lock Screen view
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.orange)
                        .font(.title2)
                }
                
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.reminderTitle)
                            .font(.headline)
                            .lineLimit(1)
                        
                        Text(context.attributes.reminderDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack {
                        Text(timerText(remaining: context.state.timeRemaining))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(statusColor(context.state.status))
                        
                        Text(context.state.status == .overdue ? "overdue" : "remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Button(intent: DismissReminderIntent(reminderId: context.attributes.reminderId.uuidString)) {
                            Label("Dismiss", systemImage: "checkmark")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        
                        Spacer()
                        
                        Button(intent: SnoozeReminderIntent(reminderId: context.attributes.reminderId.uuidString)) {
                            Label("Snooze", systemImage: "clock.arrow.circlepath")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                }
            } compactLeading: {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(timerText(remaining: context.state.timeRemaining))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor(context.state.status))
            } minimal: {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func timerText(remaining: TimeInterval) -> String {
        let absRemaining = abs(remaining)
        
        if absRemaining < 60 {
            return "\(Int(absRemaining))s"
        } else if absRemaining < 3600 {
            return "\(Int(absRemaining / 60))m"
        } else if absRemaining < 86400 {
            let hours = Int(absRemaining / 3600)
            let mins = Int((absRemaining.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(mins)m"
        } else {
            return "\(Int(absRemaining / 86400))d"
        }
    }
    
    private func statusColor(_ status: ReminderAttributes.ContentState.ReminderStatus) -> Color {
        switch status {
        case .upcoming: return .primary
        case .imminent: return .orange
        case .overdue: return .red
        }
    }
}

// MARK: - Lock Screen View
@available(iOS 16.1, *)
struct LockScreenView: View {
    let context: ActivityViewContext<ReminderAttributes>
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: "bell.fill")
                .font(.title)
                .foregroundStyle(.orange)
                .frame(width: 44, height: 44)
                .background(.orange.opacity(0.2))
                .clipShape(Circle())
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.reminderTitle)
                    .font(.headline)
                
                if !context.attributes.reminderDescription.isEmpty {
                    Text(context.attributes.reminderDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Text("Due: \(context.attributes.dueDate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Timer
            VStack {
                Text(timerText(remaining: context.state.timeRemaining))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(statusColor(context.state.status))
                
                Text(context.state.status == .overdue ? "overdue" : "left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private func timerText(remaining: TimeInterval) -> String {
        let absRemaining = abs(remaining)
        
        if absRemaining < 60 {
            return "\(Int(absRemaining))s"
        } else if absRemaining < 3600 {
            return "\(Int(absRemaining / 60))m"
        } else {
            let hours = Int(absRemaining / 3600)
            let mins = Int((absRemaining.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(mins)m"
        }
    }
    
    private func statusColor(_ status: ReminderAttributes.ContentState.ReminderStatus) -> Color {
        switch status {
        case .upcoming: return .primary
        case .imminent: return .orange
        case .overdue: return .red
        }
    }
}

// MARK: - App Intents for Live Activity buttons
import AppIntents

struct DismissReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Dismiss Reminder"
    
    @Parameter(title: "Reminder ID")
    var reminderId: String
    
    init() {}
    
    init(reminderId: String) {
        self.reminderId = reminderId
    }
    
    func perform() async throws -> some IntentResult {
        // Handle dismiss action
        // This would update the reminder store
        return .result()
    }
}

struct SnoozeReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Snooze Reminder"
    
    @Parameter(title: "Reminder ID")
    var reminderId: String
    
    init() {}
    
    init(reminderId: String) {
        self.reminderId = reminderId
    }
    
    func perform() async throws -> some IntentResult {
        // Handle snooze action - add 10 minutes
        return .result()
    }
}

// MARK: - Widget Bundle
@main
struct NoForgetWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            ReminderLiveActivity()
        }
    }
}
