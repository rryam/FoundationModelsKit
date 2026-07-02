import Foundation
import Testing
@testable import FoundationModelsTools

@Suite("Tool Query Identifier Tests")
struct ToolQueryIdentifierTests {
  @Test("Calendar query rows include event IDs")
  func calendarQueryRowsIncludeEventIDs() {
    let startDate = Date(timeIntervalSince1970: 1_820_000_000)
    let event = CalendarEventSummary(
      id: "event-123",
      title: "Design Review",
      startDate: startDate,
      endDate: startDate.addingTimeInterval(3_600),
      location: "Studio",
      calendarTitle: "Work",
      notes: "Bring the spec"
    )

    let output = CalendarTool.formatEventQueryResults([event])

    #expect(output.contains("Event ID: event-123"))
    #expect(output.contains("Design Review"))
  }

  @Test("Reminder query rows include reminder IDs")
  func reminderQueryRowsIncludeReminderIDs() {
    let reminder = ReminderSnapshot(
      id: "reminder-456",
      title: "Ship audit fix",
      listName: "Engineering",
      priority: 1
    )

    let output = RemindersTool.formatReminderQueryResults([reminder])

    #expect(output.contains("Reminder ID: reminder-456"))
    #expect(output.contains("Ship audit fix"))
  }

  @Test("Contact search rows include contact IDs")
  func contactSearchRowsIncludeContactIDs() {
    let contact = ContactSearchResult(
      id: "contact-789",
      givenName: "Avery",
      familyName: "Stone",
      email: "avery@example.com",
      phone: "+1 555 0100",
      organization: "Example Co"
    )

    let output = ContactsTool.formatContactSearchResults([contact])

    #expect(output.contains("Contact ID: contact-789"))
    #expect(output.contains("Avery Stone"))
  }
}

@Suite("Exa API Key Store Tests")
struct ExaAPIKeyStoreTests {
  @Test("API keys are saved outside UserDefaults")
  func apiKeysAreSavedOutsideUserDefaults() throws {
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    let store = ExaAPIKeyStore(
      service: "FoundationModelsToolsTests.\(UUID().uuidString)",
      account: "apiKey",
      legacyUserDefaults: defaults
    )
    defer { try? store.deleteAPIKey() }

    try store.saveAPIKey(" exa-test-key ")

    #expect(store.apiKey() == "exa-test-key")
    #expect(defaults.string(forKey: ExaAPIKeyStore.legacyUserDefaultsKey) == nil)
  }

  @Test("Legacy UserDefaults API key migrates to Keychain and is removed")
  func legacyUserDefaultsAPIKeyMigratesToKeychain() throws {
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    let service = "FoundationModelsToolsTests.\(UUID().uuidString)"
    let store = ExaAPIKeyStore(
      service: service,
      account: "apiKey",
      legacyUserDefaults: defaults
    )
    defer { try? store.deleteAPIKey() }

    defaults.set("legacy-exa-key", forKey: ExaAPIKeyStore.legacyUserDefaultsKey)

    #expect(store.apiKey() == "legacy-exa-key")
    #expect(defaults.string(forKey: ExaAPIKeyStore.legacyUserDefaultsKey) == nil)

    let reloadedStore = ExaAPIKeyStore(
      service: service,
      account: "apiKey",
      legacyUserDefaults: defaults
    )
    #expect(reloadedStore.apiKey() == "legacy-exa-key")
  }

  @Test("Legacy UserDefaults API key is preserved when Keychain migration fails")
  func legacyUserDefaultsAPIKeySurvivesFailedKeychainMigration() throws {
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    let store = ExaAPIKeyStore(
      service: "FoundationModelsToolsTests.\(UUID().uuidString)",
      account: "apiKey",
      legacyUserDefaults: defaults,
      keychain: ExaAPIKeychain(
        copyMatching: { _ in (errSecItemNotFound, nil) },
        update: { _, _ in errSecItemNotFound },
        add: { _, _ in errSecNotAvailable },
        delete: { _ in errSecSuccess }
      )
    )

    defaults.set("legacy-exa-key", forKey: ExaAPIKeyStore.legacyUserDefaultsKey)

    #expect(store.apiKey() == "legacy-exa-key")
    #expect(defaults.string(forKey: ExaAPIKeyStore.legacyUserDefaultsKey) == "legacy-exa-key")
  }
}
