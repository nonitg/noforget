import Foundation

/// Response from Twilio call initiation
struct TwilioCallResponse: Codable {
    let callSid: String
    let status: String
}

/// Service for initiating Twilio phone calls (Level 5)
@MainActor
class TwilioCallService: ObservableObject {
    @Published var isConfigured = false
    @Published var lastCallStatus: String?
    
    // Configure this with your backend URL
    private var backendURL: String = ""
    
    init() {
        // Load backend URL from UserDefaults or configuration
        if let savedURL = UserDefaults.standard.string(forKey: "twilioBackendURL") {
            backendURL = savedURL
            isConfigured = !savedURL.isEmpty
        }
    }
    
    /// Configure the backend URL
    func configure(backendURL: String) {
        self.backendURL = backendURL
        UserDefaults.standard.set(backendURL, forKey: "twilioBackendURL")
        isConfigured = !backendURL.isEmpty
    }
    
    /// Initiate a phone call for a reminder
    func initiateCall(for reminder: Reminder) async throws -> String {
        guard isConfigured else {
            throw TwilioError.notConfigured
        }
        
        guard let phoneNumber = reminder.phoneNumber, !phoneNumber.isEmpty else {
            throw TwilioError.missingPhoneNumber
        }
        
        guard let url = URL(string: "\(backendURL)/call") else {
            throw TwilioError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        let body: [String: String] = [
            "to": phoneNumber,
            "reminderTitle": reminder.title,
            "reminderDescription": reminder.description,
            "dueTime": formatter.string(from: reminder.dueDate)
        ]
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TwilioError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw TwilioError.serverError(statusCode: httpResponse.statusCode)
        }
        
        let callResponse = try JSONDecoder().decode(TwilioCallResponse.self, from: data)
        lastCallStatus = callResponse.status
        
        return callResponse.callSid
    }
    
    /// Check the status of a call
    func checkCallStatus(callSid: String) async throws -> String {
        guard isConfigured else {
            throw TwilioError.notConfigured
        }
        
        guard let url = URL(string: "\(backendURL)/call/status/\(callSid)") else {
            throw TwilioError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct StatusResponse: Codable {
            let status: String
        }
        
        let response = try JSONDecoder().decode(StatusResponse.self, from: data)
        lastCallStatus = response.status
        return response.status
    }
}

// MARK: - Errors
enum TwilioError: LocalizedError {
    case notConfigured
    case missingPhoneNumber
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int)
    case callFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Twilio backend not configured. Please set the backend URL in settings."
        case .missingPhoneNumber:
            return "Phone number is required for phone call reminders"
        case .invalidURL:
            return "Invalid backend URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let statusCode):
            return "Server error: \(statusCode)"
        case .callFailed(let reason):
            return "Call failed: \(reason)"
        }
    }
}
