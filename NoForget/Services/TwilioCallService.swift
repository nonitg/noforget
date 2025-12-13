import Foundation

/// Response from Twilio call initiation
struct TwilioCallResponse: Codable {
    let callSid: String?
    let status: String?
    let message: String?
    let success: Bool?
    let id: String?
    let minutesUntilCall: Int?
}

/// Response from schedule endpoint
struct ScheduleResponse: Codable {
    let success: Bool
    let id: String
    let message: String
    let minutesUntilCall: Int
}

/// Service for initiating Twilio phone calls (Level 5)
@MainActor
class TwilioCallService: ObservableObject {
    @Published var isConfigured = true
    @Published var lastCallStatus: String?
    
    // Production backend URL - no configuration needed
    private let backendURL: String = "https://noforget-backend.onrender.com"
    
    init() {
        // Backend is pre-configured, no setup required
    }
    
    /// Schedule a phone call for a reminder (calls at the reminder's due time)
    func scheduleCall(for reminder: Reminder) async throws -> String {
        guard isConfigured else {
            throw TwilioError.notConfigured
        }
        
        guard let phoneNumber = reminder.phoneNumber, !phoneNumber.isEmpty else {
            throw TwilioError.missingPhoneNumber
        }
        
        guard let url = URL(string: "\(backendURL)/schedule") else {
            throw TwilioError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        // ISO 8601 format for the call time
        let isoFormatter = ISO8601DateFormatter()
        
        let body: [String: Any] = [
            "to": phoneNumber,
            "reminderTitle": reminder.title,
            "reminderDescription": reminder.description,
            "callAt": isoFormatter.string(from: reminder.dueDate),
            "reminderId": reminder.id.uuidString
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TwilioError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorResponse["error"] {
                throw TwilioError.callFailed(errorMessage)
            }
            throw TwilioError.serverError(statusCode: httpResponse.statusCode)
        }
        
        let scheduleResponse = try JSONDecoder().decode(ScheduleResponse.self, from: data)
        lastCallStatus = "Scheduled in \(scheduleResponse.minutesUntilCall) min"
        
        print("📞 Call scheduled: \(scheduleResponse.id) - \(scheduleResponse.message)")
        
        return scheduleResponse.id
    }
    
    /// Cancel a scheduled call
    func cancelScheduledCall(reminderId: String) async {
        guard isConfigured else { return }
        
        guard let url = URL(string: "\(backendURL)/schedule/\(reminderId)") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30
        
        do {
            let _ = try await URLSession.shared.data(for: request)
            print("🗑️ Cancelled scheduled call: \(reminderId)")
        } catch {
            print("Failed to cancel scheduled call: \(error)")
        }
    }
    
    /// Initiate a phone call immediately (for testing)
    func initiateCallNow(for reminder: Reminder) async throws -> String {
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
        
        return callResponse.callSid ?? "unknown"
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
