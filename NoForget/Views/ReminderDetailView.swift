import SwiftUI

/// Detail view for creating or editing a reminder
struct ReminderDetailView: View {
    @EnvironmentObject var store: ReminderStore
    @Environment(\.dismiss) var dismiss
    
    let reminder: Reminder?
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var dueDate: Date = Date().addingTimeInterval(3600)
    @State private var notificationLevel: NotificationLevel = .standard
    @State private var phoneNumber: String = ""
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    private var isEditing: Bool { reminder != nil }
    
    var body: some View {
        NavigationStack {
            Form {
                // Basic Info Section
                Section {
                    TextField("Title", text: $title)
                        .font(.headline)
                    
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Details")
                }
                
                // Date & Time Section
                Section {
                    DatePicker(
                        "Due Date",
                        selection: $dueDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    
                    // Quick date buttons
                    HStack(spacing: 12) {
                        QuickDateButton(title: "1 hour", date: Date().addingTimeInterval(3600)) {
                            dueDate = $0
                        }
                        QuickDateButton(title: "Tomorrow", date: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()) {
                            dueDate = $0
                        }
                        QuickDateButton(title: "Next Week", date: Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()) {
                            dueDate = $0
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("When")
                }
                
                // Notification Level Section
                Section {
                    ForEach(NotificationLevel.allCases) { level in
                        NotificationLevelRow(
                            level: level,
                            isSelected: notificationLevel == level,
                            isAvailable: level.isAvailable
                        ) {
                            if level.isAvailable {
                                notificationLevel = level
                            }
                        }
                    }
                } header: {
                    Text("Intensity Level")
                } footer: {
                    Text("Higher levels ensure you don't miss important reminders")
                }
                
                // Phone Number (for Level 5)
                if notificationLevel == .phoneCall {
                    Section {
                        if store.userPhoneNumber.isEmpty {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Set your phone number in Settings first")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            HStack {
                                Image(systemName: "phone.fill")
                                    .foregroundStyle(.green)
                                Text("Will call: \(store.userPhoneNumber)")
                            }
                        }
                    } header: {
                        Text("Phone Call Settings")
                    } footer: {
                        Text("Phone number is configured in Settings")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Reminder" : "New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveReminder()
                    }
                    .disabled(title.isEmpty || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                if let reminder = reminder {
                    title = reminder.title
                    description = reminder.description
                    dueDate = reminder.dueDate
                    notificationLevel = reminder.notificationLevel
                    phoneNumber = reminder.phoneNumber ?? ""
                }
            }
        }
    }
    
    private func saveReminder() {
        guard !title.isEmpty else { return }
        
        // Validate phone number for Level 5
        if notificationLevel == .phoneCall && store.userPhoneNumber.isEmpty {
            errorMessage = "Please set your phone number in Settings first"
            showingError = true
            return
        }
        
        isSaving = true
        
        Task {
            do {
                if let existingReminder = reminder {
                    var updated = existingReminder
                    updated.title = title
                    updated.description = description
                    updated.dueDate = dueDate
                    updated.notificationLevel = notificationLevel
                    updated.phoneNumber = notificationLevel == .phoneCall ? store.userPhoneNumber : nil
                    
                    try await store.updateReminder(updated)
                } else {
                    let newReminder = Reminder(
                        title: title,
                        description: description,
                        dueDate: dueDate,
                        notificationLevel: notificationLevel,
                        phoneNumber: notificationLevel == .phoneCall ? store.userPhoneNumber : nil
                    )
                    try await store.addReminder(newReminder)
                }
                
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            
            isSaving = false
        }
    }
}

// MARK: - Quick Date Button
struct QuickDateButton: View {
    let title: String
    let date: Date
    let action: (Date) -> Void
    
    var body: some View {
        Button {
            action(date)
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notification Level Row
struct NotificationLevelRow: View {
    let level: NotificationLevel
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: level.icon)
                    .font(.title2)
                    .foregroundStyle(levelColor)
                    .frame(width: 36, height: 36)
                    .background(levelColor.opacity(0.15))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(level.title)
                            .font(.headline)
                            .foregroundStyle(isAvailable ? .primary : .secondary)
                        
                        if !isAvailable {
                            Text(unavailableReason)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title2)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.6)
    }
    
    private var levelColor: Color {
        switch level.color {
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "green": return .green
        default: return .blue
        }
    }
    
    private var unavailableReason: String {
        switch level {
        case .liveActivity: return "iOS 16.1+"
        case .alarmKit: return "iOS 26+"
        default: return ""
        }
    }
}

// MARK: - Preview
#Preview("New Reminder") {
    ReminderDetailView(reminder: nil)
        .environmentObject(ReminderStore())
}

#Preview("Edit Reminder") {
    ReminderDetailView(reminder: .sample)
        .environmentObject(ReminderStore())
}
