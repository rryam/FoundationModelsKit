//
//  ContactsTool.swift
//  FoundationLab
//
//  Created by Rudrank Riyam on 6/17/25.
//

@preconcurrency import Contacts
import Foundation
import FoundationModels
import FoundationModelsKit

/// A tool for managing contacts using the Contacts framework.
///
/// Use `ContactsTool` to search, read, and create contacts.
/// It integrates with the system Contacts app and requires appropriate permissions.
/// Creating a contact requires an app-owned confirmation; without one, `create` throws
/// ``ToolMutationExecutionError`` and nothing is written.
///
/// The following actions are supported:
/// - `search`: Search contacts by name, email, or phone number
/// - `read`: Read detailed information for a specific contact by ID
/// - `create`: Create a new contact with provided information
///
/// ```swift
/// let session = LanguageModelSession(tools: [ContactsTool(confirmation: confirmer)])
/// let response = try await session.respond(to: "Find John's phone number")
/// ```
///
/// - Important: Requires Contacts entitlement, `NSContactsUsageDescription` in Info.plist,
///   and user permission at runtime.
public struct ContactsTool: Tool {

    /// The name of the tool, used for identification.
    public let name = "manageContacts"
    /// A brief description of the tool's functionality.
    public let description = "Search and read contacts, or create a contact after host-app confirmation"

    /// Arguments for contact operations.
    @Generable
    public struct Arguments: RuntimeCompatibleGenerable {
        /// The action to perform: "search", "read", "create"
        @Guide(description: "The action to perform: 'search', 'read', 'create'")
        public var action: String

        /// Name to search for (for search action)
        @Guide(description: "Name to search for (for search action)")
        public var name: String?

        /// Contact identifier for reading
        @Guide(description: "Contact identifier for reading")
        public var contactId: String?

        /// First name for creating contact
        @Guide(description: "First name for creating contact")
        public var firstName: String?

        /// Last name for creating contact
        @Guide(description: "Last name for creating contact")
        public var lastName: String?

        /// Phone number for creating contact
        @Guide(description: "Phone number for creating contact")
        public var phoneNumber: String?

        /// Email address for creating contact
        @Guide(description: "Email address for creating contact")
        public var email: String?

        /// Organization for creating contact
        @Guide(description: "Organization for creating contact")
        public var organization: String?

        public init(
            action: String = "",
            name: String? = nil,
            contactId: String? = nil,
            firstName: String? = nil,
            lastName: String? = nil,
            phoneNumber: String? = nil,
            email: String? = nil,
            organization: String? = nil
        ) {
            self.action = action
            self.name = name
            self.contactId = contactId
            self.firstName = firstName
            self.lastName = lastName
            self.phoneNumber = phoneNumber
            self.email = email
            self.organization = organization
        }
    }

    private let store = CNContactStore()
    private let executor: ToolMutationExecutor?

    /// Creates a contacts tool that can search and read; `create` fails closed.
    public init() {
        self.executor = nil
    }

    /// Creates a contacts tool whose `create` action runs only after `confirmation` approves it.
    public init(confirmation: any ToolMutationConfirming) {
        self.executor = ToolMutationExecutor(confirmer: confirmation)
    }

    public func call(arguments: Arguments) async throws -> GeneratedContent {
        let action = arguments.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if action == "create" {
            return try await confirmAndCreate(ContactDraft(arguments))
        }

        let authorized = await requestAccess()
        guard authorized else {
            return createErrorOutput(error: ContactsError.accessDenied)
        }

        switch action {
        case "search":
            return try searchContacts(query: arguments.name)
        case "read":
            return try readContact(contactId: arguments.contactId)
        default:
            return createErrorOutput(error: ContactsError.invalidAction)
        }
    }

    private func confirmAndCreate(_ draft: ContactDraft) async throws -> GeneratedContent {
        guard !draft.firstName.isEmpty else {
            return createErrorOutput(error: ContactsError.missingName)
        }

        let request = ToolMutationRequest(
            toolName: name,
            action: "create",
            summary: "Create contact '\(draft.fullName)'",
            details: draft.details
        )
        guard let executor else {
            throw ToolMutationExecutionError.confirmationRequired(for: request)
        }

        return try await executor.execute(
            request,
            resourceID: { content in try? content.value(String.self, forProperty: "contactId") },
            operation: {
                guard await requestAccess() else {
                    throw ToolMutationOperationError(
                        failureDescription: ContactsError.accessDenied.localizedDescription,
                        commitState: .notAttempted
                    )
                }
                return try createContact(draft)
            }
        )
        .value
    }

    private func requestAccess() async -> Bool {
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    private func searchContacts(query: String?) throws -> GeneratedContent {
        guard let searchQuery = query, !searchQuery.isEmpty else {
            return createErrorOutput(error: ContactsError.missingQuery)
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]

        let predicate = CNContact.predicateForContacts(matchingName: searchQuery)

        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

            if contacts.isEmpty {
                // Try searching by email or phone
                let allContacts = try store.unifiedContacts(
                    matching: NSPredicate(value: true),
                    keysToFetch: keysToFetch
                )

                let filteredContacts = allContacts.filter { contact in
                    // Check emails
                    for email in contact.emailAddresses where email.value.contains(searchQuery) {
                        return true
                    }
                    // Check phone numbers
                    for phone in contact.phoneNumbers where phone.value.stringValue.contains(searchQuery) {
                        return true
                    }
                    return false
                }

                return formatContactsOutput(
                    contacts: filteredContacts.map(ContactSearchResult.init),
                    query: searchQuery
                )
            }

            return formatContactsOutput(contacts: contacts.map(ContactSearchResult.init), query: searchQuery)
        } catch {
            return createErrorOutput(error: error)
        }
    }

    private func readContact(contactId: String?) throws -> GeneratedContent {
        guard let id = contactId else {
            return createErrorOutput(error: ContactsError.missingContactId)
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor
        ]

        do {
            let contact = try store.unifiedContact(withIdentifier: id, keysToFetch: keysToFetch)

            var addresses: [String] = []
            for address in contact.postalAddresses {
                let value = address.value
                let formatted = "\(value.street), \(value.city), \(value.state) \(value.postalCode)"
                addresses.append(formatted)
            }

            return GeneratedContent(properties: [
                "status": "success",
                "contactId": contact.identifier,
                "givenName": contact.givenName,
                "familyName": contact.familyName,
                "fullName": "\(contact.givenName) \(contact.familyName)".trimmingCharacters(
                    in: .whitespaces),
                "organization": contact.organizationName,
                "emails": contact.emailAddresses.map { $0.value as String },
                "phoneNumbers": contact.phoneNumbers.map { $0.value.stringValue },
                "addresses": addresses,
                "birthday": contact.birthday?.date?.description ?? "",
                "note": contact.note
            ])
        } catch {
            return createErrorOutput(error: error)
        }
    }

    private func createContact(_ draft: ContactDraft) throws -> GeneratedContent {
        let newContact = CNMutableContact()
        newContact.givenName = draft.firstName

        if let lastName = draft.lastName {
            newContact.familyName = lastName
        }

        if let email = draft.email {
            newContact.emailAddresses = [
                CNLabeledValue(label: CNLabelHome, value: NSString(string: email))
            ]
        }

        if let phone = draft.phoneNumber {
            newContact.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))
            ]
        }

        if let org = draft.organization {
            newContact.organizationName = org
        }

        let saveRequest = CNSaveRequest()
        saveRequest.add(newContact, toContainerWithIdentifier: nil)

        do {
            try store.execute(saveRequest)
        } catch {
            throw ToolMutationOperationError(
                failureDescription: error.localizedDescription,
                commitState: .notCommitted
            )
        }

        return GeneratedContent(properties: [
            "status": "success",
            "message": "Contact created successfully",
            "contactId": newContact.identifier,
            "givenName": newContact.givenName,
            "familyName": newContact.familyName,
            "fullName": "\(newContact.givenName) \(newContact.familyName)".trimmingCharacters(
                in: .whitespaces),
            "email": draft.email ?? "",
            "phoneNumber": draft.phoneNumber ?? "",
            "organization": draft.organization ?? ""
        ])
    }

    private func formatContactsOutput(contacts: [ContactSearchResult], query: String) -> GeneratedContent {
        var contactsDescription = Self.formatContactSearchResults(contacts)

        if contactsDescription.isEmpty {
            contactsDescription = "No contacts found matching '\(query)'"
        }

        return GeneratedContent(properties: [
            "status": "success",
            "query": query,
            "count": contacts.count,
            "contactIds": contacts.map(\.id),
            "results": contactsDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            "message": "Found \(contacts.count) contact(s) matching '\(query)'"
        ])
    }

    private func createErrorOutput(error: Error) -> GeneratedContent {
        GeneratedContent(properties: [
            "status": "error",
            "error": error.localizedDescription,
            "message": "Failed to perform contact operation"
        ])
    }
}

struct ContactDraft: Sendable {
    let firstName: String
    let lastName: String?
    let phoneNumber: String?
    let email: String?
    let organization: String?

    init(_ arguments: ContactsTool.Arguments) {
        self.firstName = arguments.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.lastName = arguments.lastName
        self.phoneNumber = arguments.phoneNumber
        self.email = arguments.email
        self.organization = arguments.organization
    }

    var fullName: String {
        [firstName, lastName ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    var details: [ToolMutationDetail] {
        [
            ("First Name", firstName),
            ("Last Name", lastName),
            ("Phone", phoneNumber),
            ("Email", email),
            ("Organization", organization)
        ].compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return ToolMutationDetail(label: label, value: value)
        }
    }
}

struct ContactSearchResult: Sendable {
    let id: String
    let givenName: String
    let familyName: String
    let email: String?
    let phone: String?
    let organization: String?

    init(
        id: String,
        givenName: String,
        familyName: String,
        email: String? = nil,
        phone: String? = nil,
        organization: String? = nil
    ) {
        self.id = id
        self.givenName = givenName
        self.familyName = familyName
        self.email = email
        self.phone = phone
        self.organization = organization
    }

    init(contact: CNContact) {
        self.id = contact.identifier
        self.givenName = contact.givenName
        self.familyName = contact.familyName
        self.email = contact.emailAddresses.first?.value as String?
        self.phone = contact.phoneNumbers.first?.value.stringValue
        self.organization = contact.organizationName.isEmpty ? nil : contact.organizationName
    }
}

extension ContactsTool {
    static func formatContactSearchResults(_ contacts: [ContactSearchResult]) -> String {
        var contactsDescription = ""

        for (index, contact) in contacts.enumerated() {
            let name = "\(contact.givenName) \(contact.familyName)"
                .trimmingCharacters(in: .whitespaces)
            let email = contact.email ?? "No email"
            let phone = contact.phone ?? "No phone"
            let org = contact.organization.map { " (\($0))" } ?? ""

            contactsDescription +=
                "\(index + 1). \(name)\(org) - Contact ID: \(contact.id), Email: \(email), Phone: \(phone)\n"
        }

        return contactsDescription
    }
}

enum ContactsError: Error, LocalizedError {
    case accessDenied
    case invalidAction
    case missingQuery
    case missingContactId
    case missingName

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to contacts denied. Please grant permission in Settings."
        case .invalidAction:
            return "Invalid action. Use 'search', 'read', or 'create'."
        case .missingQuery:
            return "Search query is required."
        case .missingContactId:
            return "Contact ID is required."
        case .missingName:
            return "Given name is required to create a contact."
        }
    }
}
