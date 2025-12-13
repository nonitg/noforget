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
                
                // Step content
                TabView(selection: $currentStep) {
                    step1Welcome.tag(1)
                    step2VerifyPhone.tag(2)
                    step3AddContact.tag(3)
                    step4EmergencyBypass.tag(4)
                    step5Complete.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
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
        HStack(spacing: 4) {
            ForEach(1...totalSteps, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2)
                    .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                    .frame(height: 4)
            }
        }
    }
    
    // MARK: - Step 1: Welcome
    
    private var step1Welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "phone.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            Text("Never Miss a Reminder")
                .font(.title)
                .fontWeight(.bold)
            
            Text("For your most important reminders, we'll call your phone to make sure you don't miss them.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "checkmark.circle.fill", text: "Calls break through Do Not Disturb")
                featureRow(icon: "checkmark.circle.fill", text: "Works even when app is closed")
                featureRow(icon: "checkmark.circle.fill", text: "Optional snooze during the call")
            }
            .padding(.top)
            
            Spacer()
            
            Button {
                withAnimation { currentStep = 2 }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Step 2: Verify Phone
    
    private var step2VerifyPhone: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text("Verify Your Number")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("We'll send a verification code to confirm this is your phone.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            VStack(spacing: 16) {
                // Country code picker + Phone number input
                HStack(spacing: 12) {
                    // Country picker
                    Menu {
                        ForEach(CountryCode.all) { country in
                            Button {
                                selectedCountry = country
                            } label: {
                                Text("\(country.flag) \(country.name) (\(country.code))")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedCountry.flag)
                                .font(.title2)
                            Text(selectedCountry.code)
                                .font(.body)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.primary)
                    
                    // Phone number input - simple and clean
                    TextField("(555) 123-4567", text: Binding(
                        get: { formattedPhoneDisplay },
                        set: { newValue in
                            // Extract only digits from input
                            let digits = newValue.filter { $0.isNumber }
                            let maxLength = selectedCountry.code == "+1" ? 10 : 12
                            rawPhoneNumber = String(digits.prefix(maxLength))
                        }
                    ))
                    .keyboardType(.phonePad)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Show full number preview
                if !rawPhoneNumber.isEmpty {
                    Text("Full number: \(phoneNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if !codeSent {
                    // Send code button
                    Button {
                        sendVerificationCode()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Send Code")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(rawPhoneNumber.count >= 7 ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(rawPhoneNumber.count < 7 || isLoading)
                } else {
                    // Verification code input
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                        TextField("Enter 6-digit code", text: $verificationCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    Button {
                        verifyCode()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isVerified ? "Verified ✓" : "Verify")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isVerified ? Color.green : (verificationCode.count == 6 ? Color.blue : Color.gray))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(verificationCode.count != 6 || isLoading || isVerified)
                    
                    Button("Resend Code") {
                        sendVerificationCode()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            if isVerified {
                Button {
                    store.savePhoneNumber(phoneNumber)
                    withAnimation { currentStep = 3 }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }
    
    // MARK: - Step 3: Add Contact
    
    private var step3AddContact: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.purple)
            
            Text("Add to Contacts")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Add our number to your contacts so you can enable Emergency Bypass.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // The phone number to add
            VStack(spacing: 8) {
                Text("Remind Line")
                    .font(.headline)
                Text(twilioNumber.isEmpty ? "Loading..." : twilioNumber)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            
            if contactService.authorizationStatus == .denied {
                // Manual instructions
                manualContactInstructions
            } else {
                // Auto-add button
                Button {
                    addContactAutomatically()
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Image(systemName: contactAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                        Text(contactAdded ? "Added to Contacts" : "Add to Contacts")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(contactAdded ? Color.green : Color.purple)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isLoading || contactAdded || twilioNumber.isEmpty)
                .padding(.horizontal)
            }
            
            Spacer()
            
            Button {
                withAnimation { currentStep = 4 }
            } label: {
                Text(contactAdded ? "Continue" : "Skip for Now")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(contactAdded ? .blue : Color(.systemGray5))
                    .foregroundColor(contactAdded ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
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
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            
            Text("Enable Emergency Bypass")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("This ensures our calls ring even when Do Not Disturb is on.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            VStack(alignment: .leading, spacing: 12) {
                instructionRow(number: "1", text: "Open the Contacts app")
                instructionRow(number: "2", text: "Find \"Remind Line\"")
                instructionRow(number: "3", text: "Tap Edit (top right)")
                instructionRow(number: "4", text: "Tap Ringtone")
                instructionRow(number: "5", text: "Turn on Emergency Bypass")
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            
            Text("Without this, calls may be silenced when your phone is on Do Not Disturb.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button {
                    withAnimation { currentStep = 5 }
                } label: {
                    Text("I've Done This")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Button {
                    withAnimation { currentStep = 5 }
                } label: {
                    Text("Skip for Now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Step 5: Complete
    
    private var step5Complete: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            
            Text("All Set!")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Phone call reminders are now enabled.")
                .font(.body)
                .foregroundStyle(.secondary)
            
            // Summary
            VStack(alignment: .leading, spacing: 12) {
                summaryRow(icon: "phone.fill", label: "Your number", value: phoneNumber, success: isVerified)
                summaryRow(icon: "person.crop.circle", label: "Contact", value: contactAdded ? "Added" : "Not added", success: contactAdded)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            
            Spacer()
            
            Button {
                store.setCallOnboardingCompleted(true)
                dismiss()
            } label: {
                Text("Start Using Call Reminders")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Helper Views
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
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
        HStack {
            Image(systemName: icon)
                .foregroundStyle(success ? .green : .secondary)
                .frame(width: 24)
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
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
