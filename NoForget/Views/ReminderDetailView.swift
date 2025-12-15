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
    @State private var showingEnableCallsAlert = false
    @State private var showingSettingsForCalls = false
    
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
                } header: {
                    Text("When")
                }
                
                // Notification Level Section
                Section {
                    ForEach(NotificationLevel.allCases) { level in
                        NotificationLevelRow(
                            level: level,
                            isSelected: notificationLevel == level,
                            isAvailable: level.isAvailable(callOnboardingCompleted: store.callOnboardingCompleted)
                        ) {
                            if level.isAvailable(callOnboardingCompleted: store.callOnboardingCompleted) {
                                let selection = UISelectionFeedbackGenerator()
                                selection.selectionChanged()
                                notificationLevel = level
                            } else if level == .phoneCall {
                                showingEnableCallsAlert = true
                            }
                        }
                    }
                } header: {
                    Text("Intensity Level")
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
            .scrollDismissesKeyboard(.interactively)
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .alert("Enable Phone Calls?", isPresented: $showingEnableCallsAlert) {
                Button("Open Settings") { showingSettingsForCalls = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Set up phone call reminders to get called for important tasks.")
            }
            .sheet(isPresented: $showingSettingsForCalls) {
                SettingsView()
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
                
                // Haptic feedback on success
                let success = UINotificationFeedbackGenerator()
                success.notificationOccurred(.success)
                
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            
            isSaving = false
        }
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
                    .foregroundStyle(level.levelColor)
                    .frame(width: 36, height: 36)
                    .background(level.levelColor.opacity(0.15))
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
    
    private var unavailableReason: String {
        switch level {
        case .liveActivity: return "Coming Soon"
        case .phoneCall: return "Enable in Settings"
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
