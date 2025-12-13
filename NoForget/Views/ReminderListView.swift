import SwiftUI
import UserNotifications

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
            .navigationTitle("Reminders")
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
    
    @State private var showingCallOnboarding = false
    @State private var notificationsEnabled = false
    
    // Computed binding for the toggle
    private var phoneCallsEnabled: Binding<Bool> {
        Binding(
            get: { store.callOnboardingCompleted },
            set: { newValue in
                if newValue {
                    // Turning on - show onboarding
                    showingCallOnboarding = true
                } else {
                    // Turning off - clear data
                    store.clearPhoneData()
                }
            }
        )
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Phone Call Setup Section
                Section {
                    // Toggle row
                    Toggle(isOn: phoneCallsEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "phone.fill")
                                .foregroundStyle(store.callOnboardingCompleted ? .green : .secondary)
                            Text("Phone Calls")
                        }
                    }
                    
                    // Show phone number and edit button when enabled
                    if store.callOnboardingCompleted && !store.userPhoneNumber.isEmpty {
                        HStack {
                            Text(store.userPhoneNumber)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Edit") {
                                showingCallOnboarding = true
                            }
                            .font(.subheadline)
                        }
                    }
                } header: {
                    Text("Phone Call Reminders")
                } footer: {
                    if store.callOnboardingCompleted {
                        Text("We'll call you for high-priority reminders")
                    } else {
                        Text("Get called for your most important reminders")
                    }
                }
                
                // Notifications Section
                Section {
                    HStack {
                        Image(systemName: notificationsEnabled ? "bell.badge.fill" : "bell.slash.fill")
                            .foregroundStyle(notificationsEnabled ? .green : .secondary)
                        Text("Notifications")
                        Spacer()
                        Text(notificationsEnabled ? "On" : "Off")
                            .foregroundStyle(.secondary)
                    }
                    
                    if !notificationsEnabled {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open Settings to Enable")
                        }
                    }
                } header: {
                    Text("Notifications")
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
                checkNotificationStatus()
            }
            .sheet(isPresented: $showingCallOnboarding) {
                CallOnboardingView()
            }
        }
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsEnabled = settings.authorizationStatus == .authorized
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
