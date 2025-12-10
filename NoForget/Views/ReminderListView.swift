import SwiftUI

/// Main list view displaying all reminders
struct ReminderListView: View {
    @EnvironmentObject var store: ReminderStore
    @EnvironmentObject var notificationManager: NotificationManager
    
    @State private var showingQuickAdd = false
    @State private var showingDetail = false
    @State private var selectedReminder: Reminder?
    @State private var showingSettings = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemGray6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if store.reminders.isEmpty && !store.isLoading {
                    emptyStateView
                } else {
                    reminderList
                }
            }
            .navigationTitle("Nonit Reminders")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingQuickAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingQuickAdd) {
                QuickAddView()
            }
            .sheet(item: $selectedReminder) { reminder in
                ReminderDetailView(reminder: reminder)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .refreshable {
                await store.loadReminders()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Reminders")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Tap + to create your first reminder")
                .foregroundStyle(.secondary)
            
            Button {
                showingQuickAdd = true
            } label: {
                Label("Add Reminder", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .padding(.top)
        }
    }
    
    private var reminderList: some View {
        List {
            // Overdue section
            if !store.overdueReminders.isEmpty {
                Section {
                    ForEach(store.overdueReminders) { reminder in
                        ReminderRow(reminder: reminder)
                            .onTapGesture {
                                selectedReminder = reminder
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                deleteButton(for: reminder)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                completeButton(for: reminder)
                            }
                    }
                } header: {
                    Label("Overdue", systemImage: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.headline)
                }
            }
            
            // Upcoming section
            if !store.upcomingReminders.isEmpty {
                Section {
                    ForEach(store.upcomingReminders) { reminder in
                        ReminderRow(reminder: reminder)
                            .onTapGesture {
                                selectedReminder = reminder
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                deleteButton(for: reminder)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                completeButton(for: reminder)
                            }
                    }
                } header: {
                    Label("Upcoming", systemImage: "clock")
                        .font(.headline)
                }
            }
            
            // Completed section
            if !store.completedReminders.isEmpty {
                Section {
                    ForEach(store.completedReminders) { reminder in
                        ReminderRow(reminder: reminder)
                            .onTapGesture {
                                selectedReminder = reminder
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                deleteButton(for: reminder)
                            }
                    }
                } header: {
                    Label("Completed", systemImage: "checkmark.circle")
                        .font(.headline)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Actions
    
    private func deleteButton(for reminder: Reminder) -> some View {
        Button(role: .destructive) {
            Task {
                try? await store.deleteReminder(reminder)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    private func completeButton(for reminder: Reminder) -> some View {
        Button {
            Task {
                try? await store.completeReminder(reminder)
            }
        } label: {
            Label("Complete", systemImage: "checkmark")
        }
        .tint(.green)
    }
}

// MARK: - Reminder Row
struct ReminderRow: View {
    let reminder: Reminder
    
    var body: some View {
        HStack(spacing: 12) {
            // Level indicator
            levelBadge
            
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.headline)
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
                
                HStack(spacing: 8) {
                    Text(reminder.formattedDueDate)
                        .font(.subheadline)
                        .foregroundStyle(reminder.isOverdue ? .red : .secondary)
                    
                    if !reminder.description.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(reminder.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Status indicator
            if reminder.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if reminder.isOverdue {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var levelBadge: some View {
        Image(systemName: reminder.notificationLevel.icon)
            .font(.title3)
            .foregroundStyle(levelColor)
            .frame(width: 32, height: 32)
            .background(levelColor.opacity(0.15))
            .clipShape(Circle())
    }
    
    private var levelColor: Color {
        switch reminder.notificationLevel.color {
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "green": return .green
        default: return .blue
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var store: ReminderStore
    @Environment(\.dismiss) var dismiss
    
    @State private var phoneNumber: String = ""
    @State private var twilioBackendURL: String = ""
    @State private var showingPhoneHelp = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Notifications Section
                Section {
                    HStack {
                        Image(systemName: store.notificationManager.isAuthorized ? "bell.badge.fill" : "bell.slash.fill")
                            .foregroundStyle(store.notificationManager.isAuthorized ? .green : .red)
                        Text("Notifications")
                        Spacer()
                        Text(store.notificationManager.isAuthorized ? "Enabled" : "Disabled")
                            .foregroundStyle(store.notificationManager.isAuthorized ? .green : .red)
                    }
                    
                    if !store.notificationManager.isAuthorized {
                        Button {
                            Task {
                                await store.notificationManager.requestAuthorization()
                            }
                        } label: {
                            Label("Request Permissions", systemImage: "bell.badge")
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Notifications are required for reminders to work properly")
                }
                
                // Your Phone Number Section
                Section {
                    HStack {
                        TextField("+1 (555) 123-4567", text: $phoneNumber)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                        
                        if !phoneNumber.isEmpty {
                            Button {
                                store.savePhoneNumber(phoneNumber)
                            } label: {
                                Text("Save")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    
                    if !store.userPhoneNumber.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Saved: \(store.userPhoneNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Button {
                        showingPhoneHelp = true
                    } label: {
                        Label("Phone number format help", systemImage: "questionmark.circle")
                            .font(.caption)
                    }
                } header: {
                    Label("Your Phone Number", systemImage: "phone.fill")
                } footer: {
                    Text("Used for Level 5 (Phone Call) reminders. Enter in E.164 format: +1234567890")
                }
                
                // Twilio Backend Section
                Section {
                    TextField("https://your-backend.com", text: $twilioBackendURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    HStack {
                        Button("Save Backend URL") {
                            store.twilioService.configure(backendURL: twilioBackendURL)
                        }
                        .disabled(twilioBackendURL.isEmpty)
                        
                        Spacer()
                        
                        if store.twilioService.isConfigured {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Label("Twilio Backend", systemImage: "server.rack")
                } footer: {
                    Text("Deploy the backend server and enter its URL to enable phone call reminders")
                }
                
                // Sync Status Section
                Section {
                    HStack {
                        Image(systemName: store.cloudKitEnabled ? "icloud.fill" : "icloud.slash")
                            .foregroundStyle(store.cloudKitEnabled ? .blue : .secondary)
                        Text("iCloud Sync")
                        Spacer()
                        if store.isSyncing {
                            ProgressView()
                        } else {
                            Text(store.cloudKitEnabled ? "Connected" : "Offline")
                                .foregroundStyle(store.cloudKitEnabled ? .green : .secondary)
                        }
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text(store.cloudKitEnabled 
                        ? "Reminders sync across your devices via iCloud"
                        : "Sign in to iCloud to sync reminders across devices")
                }
                
                // Feature Availability Section
                Section {
                    FeatureRow(
                        name: "Standard Notifications",
                        icon: "bell",
                        color: .blue,
                        available: true
                    )
                    
                    FeatureRow(
                        name: "Time Sensitive",
                        icon: "bell.badge",
                        color: .orange,
                        available: true
                    )
                    
                    FeatureRow(
                        name: "Live Activities",
                        icon: "clock.badge.exclamationmark",
                        color: .purple,
                        available: store.liveActivityManager.isAvailable,
                        requirement: "iOS 16.1+"
                    )
                    
                    FeatureRow(
                        name: "AlarmKit",
                        icon: "alarm",
                        color: .red,
                        available: false,
                        requirement: "Coming Soon"
                    )
                    
                    FeatureRow(
                        name: "Phone Call",
                        icon: "phone.fill",
                        color: .green,
                        available: store.twilioService.isConfigured && !store.userPhoneNumber.isEmpty,
                        requirement: store.twilioService.isConfigured ? "Set phone number" : "Configure backend"
                    )
                } header: {
                    Text("Feature Availability")
                }
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Reminders")
                        Spacer()
                        Text("\(store.reminders.count)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                phoneNumber = store.userPhoneNumber
                twilioBackendURL = UserDefaults.standard.string(forKey: "twilioBackendURL") ?? ""
            }
            .alert("Phone Number Format", isPresented: $showingPhoneHelp) {
                Button("OK") {}
            } message: {
                Text("Enter your phone number in E.164 format:\n\n• Start with +\n• Include country code\n• No spaces or dashes\n\nExamples:\n• US: +14155551234\n• UK: +447911123456")
            }
        }
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let name: String
    let icon: String
    let color: Color
    let available: Bool
    var requirement: String? = nil
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(name)
            
            Spacer()
            
            if available {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let requirement = requirement {
                Text(requirement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}


// MARK: - Preview
#Preview {
    ReminderListView()
        .environmentObject(ReminderStore())
        .environmentObject(NotificationManager())
}
