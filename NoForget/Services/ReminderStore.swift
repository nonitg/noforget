import Foundation

/// Local-only reminder storage using UserDefaults
@MainActor
class ReminderStore: ObservableObject {
    @Published var reminders: [Reminder] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var userPhoneNumber: String = ""
    
    private let localCacheKey = "cachedReminders"
    private let phoneNumberKey = "userPhoneNumber"
    
    // Services for scheduling
    let notificationManager = NotificationManager()
    let liveActivityManager = LiveActivityManager()
    let twilioService = TwilioCallService()
    
    init() {
        // Load cached reminders immediately
        loadFromCache()
        
        // Load saved phone number
        userPhoneNumber = UserDefaults.standard.string(forKey: phoneNumberKey) ?? ""
    }
    
    // MARK: - Phone Number Settings
    
    func savePhoneNumber(_ number: String) {
        userPhoneNumber = number
        UserDefaults.standard.set(number, forKey: phoneNumberKey)
    }
    
    // MARK: - Call Onboarding State
    
    @Published var callOnboardingCompleted: Bool = UserDefaults.standard.bool(forKey: "callOnboardingCompleted")
    
    func setCallOnboardingCompleted(_ completed: Bool) {
        callOnboardingCompleted = completed
        UserDefaults.standard.set(completed, forKey: "callOnboardingCompleted")
    }
    
    /// Clear phone number and disable phone call reminders
    func clearPhoneData() {
        userPhoneNumber = ""
        UserDefaults.standard.removeObject(forKey: phoneNumberKey)
        callOnboardingCompleted = false
        UserDefaults.standard.set(false, forKey: "callOnboardingCompleted")
    }
    
    // MARK: - CRUD Operations
    
    /// Load all reminders from local cache
    func loadReminders() async {
        isLoading = true
        error = nil
        
        // Data is already loaded in init()
        isLoading = false
    }
    
    /// Add a new reminder
    func addReminder(_ reminder: Reminder) async throws {
        // Apply phone number from settings if this is a phone call reminder
        var reminderToSave = reminder
        if reminder.notificationLevel == .phoneCall && (reminder.phoneNumber?.isEmpty ?? true) {
            reminderToSave.phoneNumber = userPhoneNumber
        }
        
        // 1. Save locally
        reminders.append(reminderToSave)
        reminders.sort { $0.dueDate < $1.dueDate }
        saveToCache()
        
        // 2. Schedule notification based on level
        await scheduleForLevel(reminderToSave)
    }
    
    /// Update an existing reminder
    func updateReminder(_ reminder: Reminder) async throws {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else {
            throw ReminderStoreError.notFound
        }
        
        var updatedReminder = reminder
        updatedReminder.modifiedAt = Date()
        
        // Apply phone number from settings if needed
        if updatedReminder.notificationLevel == .phoneCall && (updatedReminder.phoneNumber?.isEmpty ?? true) {
            updatedReminder.phoneNumber = userPhoneNumber
        }
        
        // 1. Update locally
        let oldReminder = reminders[index]
        reminders[index] = updatedReminder
        reminders.sort { $0.dueDate < $1.dueDate }
        saveToCache()
        
        // 2. Reschedule notification
        await cancelScheduled(oldReminder)
        await scheduleForLevel(updatedReminder)
    }
    
    /// Delete a reminder
    func deleteReminder(_ reminder: Reminder) async throws {
        // 1. Delete locally
        reminders.removeAll { $0.id == reminder.id }
        saveToCache()
        
        // 2. Cancel scheduled notification
        await cancelScheduled(reminder)
    }
    
    /// Mark reminder as completed
    func completeReminder(_ reminder: Reminder) async throws {
        var updated = reminder
        updated.isCompleted = true
        try await updateReminder(updated)
    }
    
    /// Mark reminder as completed - async work only (for use after local update)
    func completeReminderAsync(_ reminder: Reminder) async throws {
        guard let existing = reminders.first(where: { $0.id == reminder.id }) else { return }
        // Schedule/cancel notifications for the updated reminder
        await cancelScheduled(existing)
    }
    
    /// Mark reminder as not completed and reschedule notifications
    func uncompleteReminder(_ reminder: Reminder) async throws {
        // Only allow if due date is in the future
        guard reminder.dueDate > Date() else {
            throw ReminderStoreError.cannotUncomplete
        }
        
        var updated = reminder
        updated.isCompleted = false
        updated.modifiedAt = Date()
        
        // Update locally
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else {
            throw ReminderStoreError.notFound
        }
        reminders[index] = updated
        reminders.sort { $0.dueDate < $1.dueDate }
        saveToCache()
        
        // Reschedule all notifications (including phone calls if applicable)
        await scheduleForLevel(updated)
    }
    
    /// Mark reminder as not completed - async work only (for use after local update)
    func uncompleteReminderAsync(_ reminder: Reminder) async throws {
        guard reminder.dueDate > Date() else { return }
        guard let existing = reminders.first(where: { $0.id == reminder.id }) else { return }
        // Reschedule notifications for the restored reminder
        await scheduleForLevel(existing)
    }
    
    /// Update reminder locally with animation support (synchronous)
    func updateReminderLocally(_ reminder: Reminder) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        var updated = reminder
        updated.modifiedAt = Date()
        reminders[index] = updated
        reminders.sort { $0.dueDate < $1.dueDate }
        saveToCache()
    }
    
    // MARK: - Notification Scheduling
    
    /// Schedule notification based on reminder level
    private func scheduleForLevel(_ reminder: Reminder) async {
        guard !reminder.isCompleted && reminder.dueDate > Date() else { return }
        
        do {
            switch reminder.notificationLevel {
            case .standard, .timeSensitive:
                try await notificationManager.scheduleNotification(for: reminder)
                
            case .liveActivity:
                // Live Activity coming soon - fallback to time-sensitive
                var fallback = reminder
                fallback.notificationLevel = .timeSensitive
                try await notificationManager.scheduleNotification(for: fallback)
                
            case .phoneCall:
                // Phone calls are scheduled via backend at reminder time
                // For now, also schedule a time-sensitive notification as backup
                var backup = reminder
                backup.notificationLevel = .timeSensitive
                try await notificationManager.scheduleNotification(for: backup)
                
                // Schedule the actual phone call (if backend configured)
                if twilioService.isConfigured {
                    await schedulePhoneCall(for: reminder)
                }
            }
        } catch {
            print("Failed to schedule notification: \(error)")
            self.error = error
        }
    }
    
    /// Schedule a phone call at reminder time via backend
    private func schedulePhoneCall(for reminder: Reminder) async {
        do {
            let scheduleId = try await twilioService.scheduleCall(for: reminder)
            print("✅ Phone call scheduled on backend: \(scheduleId) for \(reminder.title)")
        } catch {
            print("❌ Failed to schedule phone call: \(error)")
            // The backup time-sensitive notification is already scheduled
            // so the user will still get reminded, just not by phone
        }
    }
    
    /// Cancel a scheduled phone call
    private func cancelPhoneCall(for reminder: Reminder) async {
        await twilioService.cancelScheduledCall(reminderId: reminder.id.uuidString)
    }
    
    /// Cancel all scheduled notifications for a reminder
    private func cancelScheduled(_ reminder: Reminder) async {
        await notificationManager.cancelNotification(for: reminder)
        
        if #available(iOS 16.2, *) {
            await liveActivityManager.endActivity(for: reminder)
        }
        
        // Cancel phone call if it was scheduled
        if reminder.notificationLevel == .phoneCall {
            await cancelPhoneCall(for: reminder)
        }
    }
    
    // MARK: - Local Cache
    
    private func saveToCache() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: localCacheKey)
        }
    }
    
    private func loadFromCache() {
        if let data = UserDefaults.standard.data(forKey: localCacheKey),
           let cached = try? JSONDecoder().decode([Reminder].self, from: data) {
            reminders = cached
        }
    }
    
    // MARK: - Computed Properties
    
    var upcomingReminders: [Reminder] {
        reminders.filter { !$0.isCompleted && $0.dueDate > Date() }
    }
    
    var overdueReminders: [Reminder] {
        reminders.filter { !$0.isCompleted && $0.dueDate <= Date() }
    }
    
    var completedReminders: [Reminder] {
        reminders.filter { $0.isCompleted }
    }
    
    // MARK: - Smart Date Sorting
    
    /// Reminders due today (not overdue, not completed)
    var todayReminders: [Reminder] {
        reminders.filter {
            !$0.isCompleted && !$0.isOverdue &&
            Calendar.current.isDateInToday($0.dueDate)
        }
    }
    
    /// Reminders due tomorrow
    var tomorrowReminders: [Reminder] {
        reminders.filter {
            !$0.isCompleted &&
            Calendar.current.isDateInTomorrow($0.dueDate)
        }
    }
    
    /// Reminders due after tomorrow
    var laterReminders: [Reminder] {
        let calendar = Calendar.current
        let dayAfterTomorrow = calendar.startOfDay(for: Date().addingTimeInterval(86400 * 2))
        return reminders.filter {
            !$0.isCompleted && $0.dueDate >= dayAfterTomorrow
        }
    }
    
    /// Whether to use granular Today/Tomorrow/Later sections (when > 3 upcoming reminders)
    var shouldUseGranularSections: Bool {
        upcomingReminders.count > 3
    }
}

// MARK: - Errors
enum ReminderStoreError: LocalizedError {
    case notFound
    case cannotUncomplete
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Reminder not found"
        case .cannotUncomplete:
            return "Cannot uncomplete past reminders"
        }
    }
}
