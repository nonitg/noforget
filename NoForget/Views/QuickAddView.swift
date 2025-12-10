import SwiftUI

/// Quick add sheet for rapidly creating reminders
struct QuickAddView: View {
    @EnvironmentObject var store: ReminderStore
    @Environment(\.dismiss) var dismiss
    
    @State private var title: String = ""
    @State private var selectedDate: QuickDate = .today
    @State private var customDate: Date = Date().addingTimeInterval(3600)
    @State private var showCustomPicker: Bool = false
    @State private var notificationLevel: NotificationLevel = .standard
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    @FocusState private var isTitleFocused: Bool
    
    enum QuickDate: String, CaseIterable {
        case today = "Today"
        case tomorrow = "Tomorrow"
        case nextWeek = "Next Week"
        case custom = "Custom"
        
        var date: Date? {
            let calendar = Calendar.current
            switch self {
            case .today:
                return calendar.date(byAdding: .hour, value: 1, to: Date())
            case .tomorrow:
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
            case .nextWeek:
                let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()
                return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextWeek)
            case .custom:
                return nil // Uses customDate instead
            }
        }
        
        var icon: String {
            switch self {
            case .today: return "clock"
            case .tomorrow: return "sunrise"
            case .nextWeek: return "calendar"
            case .custom: return "calendar.badge.clock"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Title input
                VStack(alignment: .leading, spacing: 8) {
                    Text("What do you need to remember?")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    TextField("Enter reminder", text: $title)
                        .font(.title2)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .focused($isTitleFocused)
                }
                
                // Quick date selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("When?")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(QuickDate.allCases, id: \.self) { date in
                            QuickDateChip(
                                title: date.rawValue,
                                icon: date.icon,
                                isSelected: selectedDate == date
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedDate = date
                                    showCustomPicker = (date == .custom)
                                }
                            }
                        }
                    }
                    
                    // Custom date/time picker
                    if showCustomPicker {
                        VStack(spacing: 12) {
                            DatePicker(
                                "Date & Time",
                                selection: $customDate,
                                in: Date()...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.graphical)
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    }
                    
                    // Show selected time summary
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.blue)
                        Text(formattedSelectedDate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                
                // Quick level selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("How important?")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(NotificationLevel.allCases) { level in
                                QuickLevelChip(
                                    level: level,
                                    isSelected: notificationLevel == level
                                ) {
                                    if level.isAvailable || level == .alarmKit {
                                        notificationLevel = level
                                    }
                                }
                                .opacity(level.isAvailable || level == .alarmKit ? 1.0 : 0.5)
                            }
                        }
                    }
                    
                    // Show warning for phone call without phone number
                    if notificationLevel == .phoneCall && store.userPhoneNumber.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Set your phone number in Settings first")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(.top, 4)
                    }
                    
                    // Show info for AlarmKit
                    if notificationLevel == .alarmKit {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("AlarmKit coming soon - using Time Sensitive")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                
                Spacer()
                
                // Save button
                Button {
                    saveReminder()
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Reminder")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSave ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!canSave || isSaving)
            }
            .padding()
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                isTitleFocused = true
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var canSave: Bool {
        !title.isEmpty && !(notificationLevel == .phoneCall && store.userPhoneNumber.isEmpty)
    }
    
    private var selectedDueDate: Date {
        if selectedDate == .custom {
            return customDate
        }
        return selectedDate.date ?? Date()
    }
    
    private var formattedSelectedDate: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(selectedDueDate) {
            formatter.dateFormat = "'Today at' h:mm a"
        } else if Calendar.current.isDateInTomorrow(selectedDueDate) {
            formatter.dateFormat = "'Tomorrow at' h:mm a"
        } else {
            formatter.dateFormat = "MMM d 'at' h:mm a"
        }
        return formatter.string(from: selectedDueDate)
    }
    
    // MARK: - Actions
    
    private func saveReminder() {
        guard !title.isEmpty else { return }
        
        isSaving = true
        
        Task {
            do {
                let reminder = Reminder(
                    title: title,
                    dueDate: selectedDueDate,
                    notificationLevel: notificationLevel,
                    phoneNumber: notificationLevel == .phoneCall ? store.userPhoneNumber : nil
                )
                
                try await store.addReminder(reminder)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isSaving = false
            }
        }
    }
}

// MARK: - Quick Date Chip
struct QuickDateChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Level Chip
struct QuickLevelChip: View {
    let level: NotificationLevel
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: level.icon)
                    .font(.title3)
                Text(level.title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .frame(width: 80, height: 60)
            .background(isSelected ? levelColor : Color(.systemGray6))
            .foregroundStyle(isSelected ? .white : levelColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                // Show "Soon" badge for AlarmKit
                level == .alarmKit ?
                    Text("Soon")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(Capsule())
                        .offset(x: 0, y: -25)
                : nil
            )
        }
        .buttonStyle(.plain)
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
}

// MARK: - Preview
#Preview {
    QuickAddView()
        .environmentObject(ReminderStore())
}
