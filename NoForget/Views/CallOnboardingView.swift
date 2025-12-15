import SwiftUI

// Country codes for phone number picker
struct CountryCode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let code: String
    let flag: String
    
    static let all: [CountryCode] = [
        CountryCode(name: "United States", code: "+1", flag: "🇺🇸"),
        CountryCode(name: "Canada", code: "+1", flag: "🇨🇦"),
        CountryCode(name: "United Kingdom", code: "+44", flag: "🇬🇧"),
        CountryCode(name: "India", code: "+91", flag: "🇮🇳"),
        CountryCode(name: "Australia", code: "+61", flag: "🇦🇺"),
        CountryCode(name: "Germany", code: "+49", flag: "🇩🇪"),
        CountryCode(name: "France", code: "+33", flag: "🇫🇷"),
        CountryCode(name: "Japan", code: "+81", flag: "🇯🇵"),
        CountryCode(name: "China", code: "+86", flag: "🇨🇳"),
        CountryCode(name: "Mexico", code: "+52", flag: "🇲🇽"),
        CountryCode(name: "Brazil", code: "+55", flag: "🇧🇷"),
        CountryCode(name: "South Korea", code: "+82", flag: "🇰🇷"),
        CountryCode(name: "Italy", code: "+39", flag: "🇮🇹"),
        CountryCode(name: "Spain", code: "+34", flag: "🇪🇸"),
        CountryCode(name: "Netherlands", code: "+31", flag: "🇳🇱"),
    ]
}

/// Multi-step onboarding flow for setting up phone call reminders
struct CallOnboardingView: View {
    @EnvironmentObject var store: ReminderStore
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var contactService = ContactService()
    
    @State private var currentStep = 1
    @State private var rawPhoneNumber = ""  // Just digits, no formatting
    @State private var selectedCountry = CountryCode.all[0]  // Default to US
    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var codeSent = false
    @State private var isVerified = false
    @State private var contactAdded = false
    @State private var twilioNumber = ""
    
    // Focus state for auto-focusing verification code input
    @FocusState private var isCodeFieldFocused: Bool
    @FocusState private var isPhoneFieldFocused: Bool
    
    // Computed full phone number with country code
    private var phoneNumber: String {
        selectedCountry.code + rawPhoneNumber.filter { $0.isNumber }
    }
    
    // Format phone number for display (e.g., (555) 123-4567)
    private var formattedPhoneDisplay: String {
        let digits = rawPhoneNumber.filter { $0.isNumber }
        guard !digits.isEmpty else { return "" }
        
        // US/Canada format: (XXX) XXX-XXXX
        if selectedCountry.code == "+1" {
            var result = ""
            for (index, char) in digits.enumerated() {
                if index == 0 { result += "(" }
                if index == 3 { result += ") " }
                if index == 6 { result += "-" }
                if index < 10 { result += String(char) }
            }
            return result
        }
        
        // Generic format: XXX XXX XXXX
        var result = ""
        for (index, char) in digits.enumerated() {
            if index > 0 && index % 3 == 0 { result += " " }
            if index < 12 { result += String(char) }
        }
        return result
    }
    
    private let totalSteps = 5
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                progressBar
                    .padding(.horizontal)
                    .padding(.top)
                
                // Step content - using switch instead of TabView to prevent swipe navigation
                Group {
                    switch currentStep {
                    case 1: step1Welcome
                    case 2: step2VerifyPhone
                    case 3: step3AddContact
                    case 4: step4EmergencyBypass
                    case 5: step5Complete
                    default: step1Welcome
                    }
                }
                .animation(.easeInOut, value: currentStep)
            }
            .navigationTitle("Setup Phone Calls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                parseExistingPhoneNumber()
                fetchTwilioNumber()
            }
        }
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.blue : Color(.systemGray4))
                    .frame(width: step == currentStep ? 10 : 8, height: step == currentStep ? 10 : 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Step 1: Welcome
    
    private var step1Welcome: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Hero icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Image(systemName: "phone.circle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(.blue)
            }
            
            VStack(spacing: 12) {
                Text("Never Miss a Reminder")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("For your most important reminders, we'll call your phone to make sure you don't miss them.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "checkmark.circle.fill", text: "Calls break through Do Not Disturb")
                featureRow(icon: "checkmark.circle.fill", text: "Works even when app is closed")
                featureRow(icon: "checkmark.circle.fill", text: "Optional snooze during the call")
            }
            
            Spacer()
            
            Button {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    currentStep = 2
                }
            } label: {
                Label("Get Started", systemImage: "arrow.right")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Step 2: Verify Phone
    
    private var step2VerifyPhone: some View {
        ZStack {
            // Main content - centered
            VStack(spacing: 0) {
                Spacer()
                
                // Content area
                VStack(spacing: 32) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.12), Color.green.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 88, height: 88)
                        
                        Image(systemName: codeSent ? "message.fill" : "phone.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.green)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    
                    // Title section
                    VStack(spacing: 8) {
                        Text(codeSent ? "Enter Code" : "Verify Your Number")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if codeSent {
                            Text("Sent to \(formattedPhoneForDisplay)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("We'll text you a verification code")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: codeSent)
                    
                    // Input area
                    if codeSent {
                        codeInputArea
                    } else {
                        phoneInputArea
                    }
                }
                .padding(.horizontal, 28)
                
                Spacer()
                
                // Bottom area - only show button when entering phone
                if !codeSent {
                    sendCodeButton
                        .padding(.horizontal, 28)
                        .padding(.bottom, 20)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Dismiss keyboard when tapping outside
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    
    // Formatted phone for display
    private var formattedPhoneForDisplay: String {
        let digits = rawPhoneNumber.filter { $0.isNumber }
        if selectedCountry.code == "+1" && digits.count >= 10 {
            return "(\(String(digits.prefix(3)))) •••-\(String(digits.suffix(4)))"
        }
        return "\(selectedCountry.code) ••• \(String(digits.suffix(4)))"
    }
    
    // MARK: - Phone Input Area
    
    private var phoneInputArea: some View {
        HStack(spacing: 10) {
            // Country code picker
            Menu {
                ForEach(CountryCode.all) { country in
                    Button {
                        selectedCountry = country
                    } label: {
                        Text("\(country.flag) \(country.name) (\(country.code))")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedCountry.flag)
                        .font(.title3)
                    Text(selectedCountry.code)
                        .font(.body)
                        .fontWeight(.medium)
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .foregroundStyle(.primary)
            
            // Phone number field
            TextField("(555) 123-4567", text: Binding(
                get: { formattedPhoneDisplay },
                set: { newValue in
                    let digits = newValue.filter { $0.isNumber }
                    let maxLength = selectedCountry.code == "+1" ? 10 : 12
                    rawPhoneNumber = String(digits.prefix(maxLength))
                }
            ))
            .keyboardType(.phonePad)
            .focused($isPhoneFieldFocused)
            .font(.body.monospacedDigit())
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    // MARK: - Code Input Area
    
    private var codeInputArea: some View {
        VStack(spacing: 28) {
            // Code boxes
            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    codeBox(at: index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isCodeFieldFocused = true
            }
            
            // Hidden input
            TextField("", text: $verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isCodeFieldFocused)
                .frame(width: 0, height: 0)
                .opacity(0)
                .onChange(of: verificationCode) { _, newValue in
                    let filtered = String(newValue.prefix(6).filter { $0.isNumber })
                    if filtered != verificationCode {
                        verificationCode = filtered
                    }
                    if verificationCode.count == 6 && !isVerified && !isLoading {
                        verifyCode()
                    }
                }
            
            // Status area
            codeStatusArea
        }
        .onAppear {
            // Auto-focus when code section appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isCodeFieldFocused = true
            }
        }
    }
    
    @ViewBuilder
    private func codeBox(at index: Int) -> some View {
        let hasDigit = index < verificationCode.count
        let isActive = index == verificationCode.count && isCodeFieldFocused && !isVerified
        let digit = hasDigit ? String(verificationCode[verificationCode.index(verificationCode.startIndex, offsetBy: index)]) : ""
        
        Text(digit)
            .font(.title2)
            .fontWeight(.semibold)
            .monospacedDigit()
            .frame(width: 46, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isVerified ? Color.green.opacity(0.08) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isVerified ? Color.green.opacity(0.5) :
                        isActive ? Color.blue :
                        hasDigit ? Color(.separator).opacity(0.2) : Color.clear,
                        lineWidth: isActive ? 2 : 1
                    )
            )
            .animation(.easeOut(duration: 0.15), value: hasDigit)
            .animation(.easeOut(duration: 0.15), value: isActive)
    }
    
    @State private var cursorVisible = false
    
    @ViewBuilder
    private var codeStatusArea: some View {
        if isVerified {
            // Verified state
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text("Verified")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundStyle(.green)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.1))
            .clipShape(Capsule())
            .transition(.scale.combined(with: .opacity))
        } else if isLoading {
            // Loading state
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Verifying...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            // Action buttons
            VStack(spacing: 10) {
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    verificationCode = ""
                    sendVerificationCode()
                } label: {
                    Text("Resend Code")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        codeSent = false
                        verificationCode = ""
                    }
                } label: {
                    Text("Change Number")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
    
    // MARK: - Send Code Button
    
    private var sendCodeButton: some View {
        let canSend = rawPhoneNumber.count >= 7 && !isLoading
        
        return Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            isPhoneFieldFocused = false
            sendVerificationCode()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Text("Send Code")
                    Image(systemName: "arrow.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(canSend ? Color.blue : Color(.systemGray4))
            )
        }
        .disabled(!canSend)
        .animation(.easeInOut(duration: 0.15), value: canSend)
    }
    
    // MARK: - Step 3: Add Contact
    
    private var step3AddContact: some View {
        VStack(spacing: 28) {
            Spacer()
            
            // Hero icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.2), Color.purple.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 56))
                    .foregroundStyle(.purple)
            }
            
            VStack(spacing: 8) {
                Text("Add to Contacts")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Add our number to your contacts so you can enable Emergency Bypass.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Contact info - clean display without box
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Remind Line")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(twilioNumber.isEmpty ? "Loading..." : twilioNumber)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                
                if contactService.authorizationStatus == .denied {
                    // Copy button for manual add
                    Button {
                        UIPasteboard.general.string = twilioNumber
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Number")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.purple)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(Color.purple.opacity(0.1))
                        .clipShape(Capsule())
                    }
                } else {
                    // Auto-add button - capsule style
                    Button {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        addContactAutomatically()
                    } label: {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: contactAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                            }
                            Text(contactAdded ? "Added to Contacts" : "Add to Contacts")
                        }
                        .font(.headline)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(contactAdded ? Color.green : Color.purple)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                    .disabled(isLoading || contactAdded || twilioNumber.isEmpty)
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Continue/Skip button
            VStack(spacing: 12) {
                if contactAdded {
                    Button {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentStep = 4
                        }
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                            .font(.headline)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentStep = 4
                        }
                    } label: {
                        Text("Skip for Now")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 32)
        }
    }
    
    private var manualContactInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add manually:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            instructionRow(number: "1", text: "Copy the number above")
            instructionRow(number: "2", text: "Open the Contacts app")
            instructionRow(number: "3", text: "Tap + to add new contact")
            instructionRow(number: "4", text: "Name it \"Remind Line\"")
            instructionRow(number: "5", text: "Paste the number and save")
            
            Button {
                UIPasteboard.general.string = twilioNumber
            } label: {
                Label("Copy Number", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
    
    // MARK: - Step 4: Emergency Bypass
    
    private var step4EmergencyBypass: some View {
        VStack(spacing: 28) {
            Spacer()
            
            // Hero icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
            }
            
            VStack(spacing: 8) {
                Text("Enable Emergency Bypass")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("This ensures our calls ring even when Do Not Disturb is on.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Timeline-style instructions - cleaner without box
            VStack(alignment: .leading, spacing: 14) {
                timelineStep(icon: "person.crop.circle", text: "Open the Contacts app")
                timelineStep(icon: "magnifyingglass", text: "Find \"Remind Line\"")
                timelineStep(icon: "pencil", text: "Tap Edit (top right)")
                timelineStep(icon: "bell.fill", text: "Tap Ringtone")
                timelineStep(icon: "checkmark.circle.fill", text: "Turn on Emergency Bypass")
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        currentStep = 5
                    }
                } label: {
                    Label("I've Done This", systemImage: "checkmark")
                        .font(.headline)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        currentStep = 5
                    }
                } label: {
                    Text("Skip for Now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Step 5: Complete
    
    private var step5Complete: some View {
        VStack(spacing: 28) {
            Spacer()
            
            // Success icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.2), Color.green.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(.green)
            }
            
            VStack(spacing: 8) {
                Text("All Set!")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Phone call reminders are now enabled.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            // Summary - clean display without box
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(.green)
                        .frame(width: 24)
                    Text(phoneNumber)
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(contactAdded ? .green : .secondary)
                        .frame(width: 24)
                    Text(contactAdded ? "Contact added" : "Contact not added")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: contactAdded ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(contactAdded ? .green : .secondary)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            Button {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                store.setCallOnboardingCompleted(true)
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 14)
                    .background(.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Helper Views
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.green)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
    
    private func timelineStep(icon: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
        }
    }
    
    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.blue)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
        }
    }
    
    private func summaryRow(icon: String, label: String, value: String, success: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(success ? .green : .secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            Image(systemName: success ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(success ? .green : .secondary)
        }
    }
    
    // MARK: - Actions
    
    // Production backend URL
    private let backendURL = "https://noforget-backend.onrender.com"
    
    private func fetchTwilioNumber() {
        guard let url = URL(string: "\(backendURL)/info") else {
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let number = json["twilioNumber"] as? String {
                    await MainActor.run {
                        twilioNumber = number
                    }
                }
            } catch {
                print("❌ Failed to fetch Twilio number: \(error)")
            }
        }
    }
    
    private func sendVerificationCode() {
        guard let url = URL(string: "\(backendURL)/verify/send") else {
            errorMessage = "Invalid backend URL"
            showError = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(["phoneNumber": phoneNumber])
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to send code"])
                }
                
                await MainActor.run {
                    codeSent = true
                    isLoading = false
                    // Auto-focus the code input after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isCodeFieldFocused = true
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
    
    private func verifyCode() {
        guard let url = URL(string: "\(backendURL)/verify/check") else {
            errorMessage = "Invalid backend URL"
            showError = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let body = ["phoneNumber": phoneNumber, "code": verificationCode]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let valid = json["valid"] as? Bool {
                    await MainActor.run {
                        if valid {
                            isVerified = true
                            // Dismiss keyboard
                            isCodeFieldFocused = false
                            // Haptic feedback for success
                            let successFeedback = UINotificationFeedbackGenerator()
                            successFeedback.notificationOccurred(.success)
                            
                            // Auto-progress after a brief delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                store.savePhoneNumber(phoneNumber)
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    currentStep = 3
                                }
                            }
                        } else {
                            errorMessage = "Invalid or expired code. Please try again."
                            showError = true
                        }
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
    
    private func addContactAutomatically() {
        guard !twilioNumber.isEmpty else { return }
        
        isLoading = true
        
        Task {
            let result = await contactService.addRemindLineContact(phoneNumber: twilioNumber)
            
            await MainActor.run {
                isLoading = false
                
                switch result {
                case .success:
                    contactAdded = true
                case .failure(let error):
                    if case .permissionDenied = error {
                        // Will show manual instructions
                    } else {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
    }
    
    private func parseExistingPhoneNumber() {
        let existing = store.userPhoneNumber
        guard !existing.isEmpty else { return }
        
        // Try to match country code from the saved number
        for country in CountryCode.all {
            if existing.hasPrefix(country.code) {
                selectedCountry = country
                rawPhoneNumber = String(existing.dropFirst(country.code.count))
                return
            }
        }
        
        // Default: assume it's just the raw number without country code
        rawPhoneNumber = existing.filter { $0.isNumber }
    }
}

#Preview {
    CallOnboardingView()
        .environmentObject(ReminderStore())
}
