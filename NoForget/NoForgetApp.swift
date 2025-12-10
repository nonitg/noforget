import SwiftUI

@main
struct NoForgetApp: App {
    @StateObject private var reminderStore = ReminderStore()
    @StateObject private var notificationManager = NotificationManager()
    
    var body: some Scene {
        WindowGroup {
            ReminderListView()
                .environmentObject(reminderStore)
                .environmentObject(notificationManager)
                .task {
                    await notificationManager.requestAuthorization()
                    await reminderStore.loadReminders()
                }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 600)
        #endif
    }
}
