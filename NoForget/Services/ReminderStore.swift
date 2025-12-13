import Foundation
import CloudKit

/// Local-first reminder storage with optional CloudKit sync
@MainActor
class ReminderStore: ObservableObject {
    @Published var reminders: [Reminder] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var isSyncing = false
    @Published var cloudKitEnabled = false
    @Published var userPhoneNumber: String = ""
    
    private let container: CKContainer
    private let database: CKDatabase
    private let recordType = "Reminder"
    private let localCacheKey = "cachedReminders"
    private let phoneNumberKey = "userPhoneNumber"
    
    // Services for scheduling
    let notificationManager = NotificationManager()
    let liveActivityManager = LiveActivityManager()
    let alarmKitManager = AlarmKitManager()
    let twilioService = TwilioCallService()
    
    init() {
        // Use default container - replace with your container ID
        container = CKContainer(identifier: "iCloud.com.noforget.app")
        database = container.privateCloudDatabase
        
        // Load cached reminders immediately (local-first)
        loadFromCache()
        
        // Load saved phone number
        userPhoneNumber = UserDefaults.standard.string(forKey: phoneNumberKey) ?? ""
        
        // Check CloudKit availability in background
        Task {
            await checkCloudKitAvailability()
        }
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
    
    // MARK: - CloudKit Availability
    
    private func checkCloudKitAvailability() async {
        do {
            let status = try await container.accountStatus()
            cloudKitEnabled = (status == .available)
            
            if cloudKitEnabled {
                print("CloudKit available - sync enabled")
            } else {
                print("CloudKit not available - using local storage only")
            }
        } catch {
            print("CloudKit check failed: \(error)")
            cloudKitEnabled = false
        }
    }
    
    // MARK: - CRUD Operations
    
    /// Load all reminders (local-first, then sync from CloudKit if available)
    func loadReminders() async {
        isLoading = true
        error = nil
        
        // Local data is already loaded in init(), but sync from CloudKit if available
        if cloudKitEnabled {
            await syncFromCloudKit()
        }
        
        isLoading = false
    }
    
    /// Sync reminders from CloudKit
    private func syncFromCloudKit() async {
        guard cloudKitEnabled else { return }
        
        isSyncing = true
        
        do {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "dueDate", ascending: true)]
            
            let (results, _) = try await database.records(matching: query)
            
            var cloudReminders: [Reminder] = []
            for (_, result) in results {
                if case .success(let record) = result {
                    if let reminder = Reminder(from: record) {
                        cloudReminders.append(reminder)
                    }
                }
            }
            
            // Merge cloud data with local (cloud wins for conflicts)
            mergeReminders(cloudReminders)
            saveToCache()
            
        } catch {
            print("CloudKit sync failed: \(error)")
            // Don't set error - local data still works
        }
        
        isSyncing = false
    }
    
    /// Merge cloud reminders with local (cloud wins on conflict)
    private func mergeReminders(_ cloudReminders: [Reminder]) {
        var merged: [Reminder] = cloudReminders
        
        // Add any local-only reminders (not yet synced)
        for local in reminders {
            if !cloudReminders.contains(where: { $0.id == local.id }) {
                merged.append(local)
            }
        }
        
        reminders = merged.sorted { $0.dueDate < $1.dueDate }
    }
    
    /// Add a new reminder (saves locally first, then syncs to CloudKit)
    func addReminder(_ reminder: Reminder) async throws {
        // Apply phone number from settings if this is a phone call reminder
        var reminderToSave = reminder
        if reminder.notificationLevel == .phoneCall && (reminder.phoneNumber?.isEmpty ?? true) {
            reminderToSave.phoneNumber = userPhoneNumber
        }
        
        // 1. Save locally first (immediate)
        reminders.append(reminderToSave)
        reminders.sort { $0.dueDate < $1.dueDate }
        saveToCache()
        
        // 2. Schedule notification based on level
        await scheduleForLevel(reminderToSave)
        
        // 3. Sync to CloudKit in background (optional)
        if cloudKitEnabled {
            Task {
                await syncToCloudKit(reminderToSave)
            }
        }
    }
    
    /// Sync a single reminder to CloudKit
    private func syncToCloudKit(_ reminder: Reminder) async {
        let record = reminder.toCloudKitRecord()
        
        do {
            _ = try await database.save(record)
            print("Synced reminder to CloudKit: \(reminder.title)")
        } catch {
            print("CloudKit save failed (will retry later): \(error)")
            // Mark for retry later - could add a "needsSync" flag
        }
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
        
        // 1. Update locally first
        let oldReminder = reminders[index]
        reminders[index] = updatedReminder
        reminders.sort { $0.dueDate < $1.dueDate }
        saveToCache()
        
        // 2. Reschedule notification
        await cancelScheduled(oldReminder)
        await scheduleForLevel(updatedReminder)
        
        // 3. Sync to CloudKit in background
        if cloudKitEnabled {
            Task {
                await syncToCloudKit(updatedReminder)
            }
        }
    }
    
    /// Delete a reminder
    func deleteReminder(_ reminder: Reminder) async throws {
        // 1. Delete locally first
        reminders.removeAll { $0.id == reminder.id }
        saveToCache()
        
        // 2. Cancel scheduled notification
        await cancelScheduled(reminder)
        
        // 3. Delete from CloudKit in background
        if cloudKitEnabled {
            Task {
                await deleteFromCloudKit(reminder)
            }
        }
    }
    
    /// Delete a reminder from CloudKit
    private func deleteFromCloudKit(_ reminder: Reminder) async {
        let recordID = CKRecord.ID(recordName: reminder.id.uuidString)
        
        do {
            try await database.deleteRecord(withID: recordID)
            print("Deleted reminder from CloudKit: \(reminder.title)")
        } catch {
            print("CloudKit delete failed: \(error)")
        }
    }
    
    /// Mark reminder as completed
    func completeReminder(_ reminder: Reminder) async throws {
        var updated = reminder
        updated.isCompleted = true
        try await updateReminder(updated)
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
                if #available(iOS 16.2, *), liveActivityManager.isAvailable {
                    try await liveActivityManager.startActivity(for: reminder)
                } else {
                    // Fallback to time-sensitive
                    var fallback = reminder
                    fallback.notificationLevel = .timeSensitive
                    try await notificationManager.scheduleNotification(for: fallback)
                }
                
            case .alarmKit:
                // AlarmKit disabled - fallback to time-sensitive
                try await alarmKitManager.scheduleFallbackNotification(for: reminder, using: notificationManager)
                
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
}

// MARK: - Errors
enum ReminderStoreError: LocalizedError {
    case notFound
    case syncFailed
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Reminder not found"
        case .syncFailed:
            return "Failed to sync with iCloud"
        }
    }
}

// MARK: - CloudKit Extensions
extension Reminder {
    init?(from record: CKRecord) {
        guard let title = record["title"] as? String,
              let dueDate = record["dueDate"] as? Date,
              let levelRaw = record["notificationLevel"] as? Int,
              let level = NotificationLevel(rawValue: levelRaw),
              let isCompleted = record["isCompleted"] as? Bool,
              let createdAt = record["createdAt"] as? Date,
              let modifiedAt = record["modifiedAt"] as? Date
        else {
            return nil
        }
        
        guard let id = UUID(uuidString: record.recordID.recordName) else {
            return nil
        }
        
        self.id = id
        self.title = title
        self.description = record["description"] as? String ?? ""
        self.dueDate = dueDate
        self.notificationLevel = level
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.phoneNumber = record["phoneNumber"] as? String
        self.twilioCallSid = record["twilioCallSid"] as? String
    }
    
    func toCloudKitRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: "Reminder", recordID: recordID)
        
        record["title"] = title
        record["description"] = description
        record["dueDate"] = dueDate
        record["notificationLevel"] = notificationLevel.rawValue
        record["isCompleted"] = isCompleted
        record["createdAt"] = createdAt
        record["modifiedAt"] = modifiedAt
        record["phoneNumber"] = phoneNumber
        record["twilioCallSid"] = twilioCallSid
        
        return record
    }
}
