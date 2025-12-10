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
                        Image(systemName: "plus")
                            .font(.title2)
                            .fontWeight(.semibold)
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
                ReminderDetailView(reminder: nil)
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
    
    var body: some View {
        NavigationStack {
            Form {
                // Phone Call Setup Section
                Section {
                    // Phone number input
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundStyle(.green)
                            .frame(width: 24)
                        TextField("+1234567890", text: $phoneNumber)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                        
                        if !phoneNumber.isEmpty && phoneNumber != store.userPhoneNumber {
                            Button("Save") {
                                store.savePhoneNumber(phoneNumber)
                            }
                            .fontWeight(.semibold)
                        }
                    }
                    
                    // Backend URL input
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        TextField("Backend URL", text: $twilioBackendURL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                        
                        if !twilioBackendURL.isEmpty {
                            Button("Save") {
                                store.twilioService.configure(backendURL: twilioBackendURL)
                            }
                            .fontWeight(.semibold)
                        }
                    }
                    
                    // Status indicator
                    if store.twilioService.isConfigured && !store.userPhoneNumber.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Phone calls enabled")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Phone Call Reminders")
                } footer: {
                    Text("Enter your phone number (e.g. +14155551234) and backend URL to enable call reminders")
                }
                
                // Notifications & Sync Section
                Section {
                    // Notifications row
                    HStack {
                        Image(systemName: store.notificationManager.isAuthorized ? "bell.badge.fill" : "bell.slash.fill")
                            .foregroundStyle(store.notificationManager.isAuthorized ? .green : .red)
                            .frame(width: 24)
                        Text("Notifications")
                        Spacer()
                        Text(store.notificationManager.isAuthorized ? "On" : "Off")
                            .foregroundStyle(.secondary)
                    }
                    
                    if !store.notificationManager.isAuthorized {
                        Button {
                            Task {
                                await store.notificationManager.requestAuthorization()
                            }
                        } label: {
                            Text("Enable Notifications")
                        }
                    }
                    
                    // iCloud row
                    HStack {
                        Image(systemName: store.cloudKitEnabled ? "icloud.fill" : "icloud.slash")
                            .foregroundStyle(store.cloudKitEnabled ? .blue : .secondary)
                            .frame(width: 24)
                        Text("iCloud Sync")
                        Spacer()
                        if store.isSyncing {
                            ProgressView()
                        } else {
                            Text(store.cloudKitEnabled ? "On" : "Off")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Notifications & Sync")
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
        }
    }
}


// MARK: - Preview
#Preview {
    ReminderListView()
        .environmentObject(ReminderStore())
        .environmentObject(NotificationManager())
}
