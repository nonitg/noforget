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
    @State private var isCompletedExpanded = false
    
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
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
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
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
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
            .buttonStyle(ScaleButtonStyle())
            .padding(.top)
        }
    }
    
    private var reminderList: some View {
        List {
            // Overdue section
            if !store.overdueReminders.isEmpty {
                overdueSection
            }
            
            // Smart sorting: use Today/Tomorrow/Later when many reminders, otherwise simple Upcoming
            if store.shouldUseGranularSections {
                if !store.todayReminders.isEmpty {
                    todaySection
                }
                if !store.tomorrowReminders.isEmpty {
                    tomorrowSection
                }
                if !store.laterReminders.isEmpty {
                    laterSection
                }
            } else if !store.upcomingReminders.isEmpty {
                upcomingSection
            }
            
            // Completed section (collapsible)
            if !store.completedReminders.isEmpty {
                completedSection
            }
        }
        .listStyle(.insetGrouped)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.reminders)
    }
    
    // MARK: - Section Views
    
    private var overdueSection: some View {
        Section {
            reminderRows(for: store.overdueReminders, allowComplete: true, allowUncomplete: false)
        } header: {
            Label("Overdue", systemImage: "exclamationmark.circle")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.red)
        }
    }
    
    private var upcomingSection: some View {
        Section {
            reminderRows(for: store.upcomingReminders, allowComplete: true, allowUncomplete: false)
        } header: {
            Label("Upcoming", systemImage: "clock")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
        }
    }
    
    private var todaySection: some View {
        Section {
            reminderRows(for: store.todayReminders, allowComplete: true, allowUncomplete: false)
        } header: {
            Label("Today", systemImage: "sun.max")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
        }
    }
    
    private var tomorrowSection: some View {
        Section {
            reminderRows(for: store.tomorrowReminders, allowComplete: true, allowUncomplete: false)
        } header: {
            Label("Tomorrow", systemImage: "sunrise")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
        }
    }
    
    private var laterSection: some View {
        Section {
            reminderRows(for: store.laterReminders, allowComplete: true, allowUncomplete: false)
        } header: {
            Label("Later", systemImage: "calendar")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
        }
    }
    
    private var completedSection: some View {
        Section {
            if isCompletedExpanded {
                reminderRows(for: store.completedReminders, allowComplete: false, allowUncomplete: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isCompletedExpanded.toggle()
                }
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            } label: {
                HStack {
                    Label("Completed (\(store.completedReminders.count))", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                        .rotationEffect(.degrees(isCompletedExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Reminder Rows Helper
    
    @ViewBuilder
    private func reminderRows(for reminders: [Reminder], allowComplete: Bool, allowUncomplete: Bool) -> some View {
        ForEach(Array(reminders.enumerated()), id: \.element.id) { index, reminder in
            VStack(spacing: 0) {
                ReminderRow(reminder: reminder)
                    .padding(.vertical, 8)
                    .onTapGesture {
                        let selection = UISelectionFeedbackGenerator()
                        selection.selectionChanged()
                        selectedReminder = reminder
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        deleteButton(for: reminder)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: allowComplete || (allowUncomplete && reminder.dueDate > Date())) {
                        if allowComplete {
                            completeButton(for: reminder)
                        } else if allowUncomplete && reminder.dueDate > Date() {
                            uncompleteButton(for: reminder)
                        }
                    }
                
                // Divider between rows (not after last one)
                if index < reminders.count - 1 {
                    Divider()
                        .padding(.leading, 56)
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(
                RoundedCornersShape(
                    corners: cornerMask(for: index, in: reminders),
                    radius: 10
                )
                .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }
    
    // MARK: - Actions
    
    private func deleteButton(for reminder: Reminder) -> some View {
        Button(role: .destructive) {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            Task {
                try? await store.deleteReminder(reminder)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    private func completeButton(for reminder: Reminder) -> some View {
        Button {
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.success)
            Task {
                try? await store.completeReminder(reminder)
            }
        } label: {
            Label("Complete", systemImage: "checkmark")
        }
        .tint(.green)
    }
    
    private func uncompleteButton(for reminder: Reminder) -> some View {
        Button {
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.success)
            Task {
                try? await store.uncompleteReminder(reminder)
            }
        } label: {
            Label("Restore", systemImage: "arrow.uturn.backward")
        }
        .tint(.orange)
    }
    
    // MARK: - Corner Helpers
    
    private func cornerMask(for index: Int, in reminders: [Reminder]) -> UIRectCorner {
        if reminders.count == 1 {
            return .allCorners
        } else if index == 0 {
            return [.topLeft, .topRight]
        } else if index == reminders.count - 1 {
            return [.bottomLeft, .bottomRight]
        } else {
            return []
        }
    }
}

// MARK: - Rounded Corners Shape
struct RoundedCornersShape: Shape {
    var corners: UIRectCorner
    var radius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
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
        .contentShape(Rectangle())
    }
    
    private var levelBadge: some View {
        Image(systemName: reminder.notificationLevel.icon)
            .font(.title3)
            .foregroundStyle(reminder.notificationLevel.levelColor)
            .frame(width: 32, height: 32)
            .background(reminder.notificationLevel.levelColor.opacity(0.15))
            .clipShape(Circle())
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
