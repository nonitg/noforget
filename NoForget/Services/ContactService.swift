import Foundation
import Contacts

/// Service for managing contacts, specifically adding the Remind Line contact
class ContactService: ObservableObject {
    
    @Published var authorizationStatus: CNAuthorizationStatus = .notDetermined
    @Published var contactExists = false
    
    private let contactStore = CNContactStore()
    private let contactName = "Remind Line"
    
    init() {
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    func checkAuthorizationStatus() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }
    
    func requestAccess() async -> Bool {
        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            await MainActor.run {
                checkAuthorizationStatus()
            }
            return granted
        } catch {
            print("❌ Contact access request failed: \(error)")
            return false
        }
    }
    
    // MARK: - Contact Management
    
    /// Add the Remind Line contact with the given phone number
    func addRemindLineContact(phoneNumber: String) async -> Result<Void, ContactError> {
        // First ensure we have permission
        if authorizationStatus != .authorized {
            let granted = await requestAccess()
            if !granted {
                return .failure(.permissionDenied)
            }
        }
        
        // Check if contact already exists
        if let existingContact = findRemindLineContact() {
            // Update if number is different
            if let existingNumber = existingContact.phoneNumbers.first?.value.stringValue,
               existingNumber == phoneNumber {
                return .success(())  // Already exists with same number
            }
            
            // Update the existing contact
            return await updateContact(existingContact, withNumber: phoneNumber)
        }
        
        // Create new contact
        return await createContact(withNumber: phoneNumber)
    }
    
    /// Check if Remind Line contact already exists
    func checkContactExists(phoneNumber: String) -> Bool {
        guard let contact = findRemindLineContact() else {
            contactExists = false
            return false
        }
        
        let hasCorrectNumber = contact.phoneNumbers.contains { 
            $0.value.stringValue.replacingOccurrences(of: " ", with: "") == 
            phoneNumber.replacingOccurrences(of: " ", with: "")
        }
        
        contactExists = hasCorrectNumber
        return hasCorrectNumber
    }
    
    // MARK: - Private Helpers
    
    private func findRemindLineContact() -> CNContact? {
        let predicate = CNContact.predicateForContacts(matchingName: contactName)
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]
        
        do {
            let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            return contacts.first
        } catch {
            print("❌ Error fetching contacts: \(error)")
            return nil
        }
    }
    
    private func createContact(withNumber phoneNumber: String) async -> Result<Void, ContactError> {
        let contact = CNMutableContact()
        contact.givenName = contactName
        contact.phoneNumbers = [
            CNLabeledValue(
                label: CNLabelPhoneNumberMain,
                value: CNPhoneNumber(stringValue: phoneNumber)
            )
        ]
        
        // Add a note explaining what this contact is for
        contact.note = "NoForget app reminder calls. Enable Emergency Bypass in ringtone settings to ensure calls come through."
        
        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)
        
        do {
            try contactStore.execute(saveRequest)
            await MainActor.run {
                contactExists = true
            }
            print("✅ Created Remind Line contact")
            return .success(())
        } catch {
            print("❌ Failed to create contact: \(error)")
            return .failure(.saveFailed(error.localizedDescription))
        }
    }
    
    private func updateContact(_ contact: CNContact, withNumber phoneNumber: String) async -> Result<Void, ContactError> {
        guard let mutableContact = contact.mutableCopy() as? CNMutableContact else {
            return .failure(.saveFailed("Could not update contact"))
        }
        
        mutableContact.phoneNumbers = [
            CNLabeledValue(
                label: CNLabelPhoneNumberMain,
                value: CNPhoneNumber(stringValue: phoneNumber)
            )
        ]
        
        let saveRequest = CNSaveRequest()
        saveRequest.update(mutableContact)
        
        do {
            try contactStore.execute(saveRequest)
            await MainActor.run {
                contactExists = true
            }
            print("✅ Updated Remind Line contact")
            return .success(())
        } catch {
            print("❌ Failed to update contact: \(error)")
            return .failure(.saveFailed(error.localizedDescription))
        }
    }
}

// MARK: - Error Types

enum ContactError: Error, LocalizedError {
    case permissionDenied
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Contact access was denied. Please add the contact manually."
        case .saveFailed(let message):
            return "Failed to save contact: \(message)"
        }
    }
}
