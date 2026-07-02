//
//  ExaAPIKeyStore.swift
//  FoundationModelsTools
import Foundation
import Security

/// Stores the Exa API key in the system Keychain.
public struct ExaAPIKeyStore: @unchecked Sendable {
  public static let shared = ExaAPIKeyStore()

  static let legacyUserDefaultsKey = "exaAPIKey"

  private let service: String
  private let account: String
  private let legacyUserDefaults: UserDefaults

  public init(
    service: String = "com.rryam.FoundationModelsTools.exa",
    account: String = "apiKey",
    legacyUserDefaults: UserDefaults = .standard
  ) {
    self.service = service
    self.account = account
    self.legacyUserDefaults = legacyUserDefaults
  }

  /// Returns the stored API key, migrating the legacy UserDefaults value if needed.
  public func apiKey() -> String {
    if let key = keychainAPIKey(), !key.isEmpty {
      return key
    }

    guard
      let legacyKey = legacyUserDefaults.string(forKey: Self.legacyUserDefaultsKey)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !legacyKey.isEmpty
    else {
      return ""
    }

    do {
      try saveAPIKey(legacyKey)
      legacyUserDefaults.removeObject(forKey: Self.legacyUserDefaultsKey)
    } catch {
      return ""
    }

    return legacyKey
  }

  /// Saves the API key in Keychain. Passing an empty string deletes the stored key.
  public func saveAPIKey(_ apiKey: String) throws {
    let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedKey.isEmpty else {
      try deleteAPIKey()
      return
    }

    let encodedKey = Data(trimmedKey.utf8)
    let updateStatus = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData: encodedKey] as CFDictionary
    )

    switch updateStatus {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var attributes = query
      attributes[kSecValueData as String] = encodedKey
      let addStatus = SecItemAdd(attributes as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw ExaAPIKeyStoreError.keychainWriteFailed(addStatus)
      }
    default:
      throw ExaAPIKeyStoreError.keychainWriteFailed(updateStatus)
    }
  }

  public func deleteAPIKey() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw ExaAPIKeyStoreError.keychainDeleteFailed(status)
    }
  }

  private func keychainAPIKey() -> String? {
    var lookup = query
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}

public enum ExaAPIKeyStoreError: Error, LocalizedError {
  case keychainWriteFailed(OSStatus)
  case keychainDeleteFailed(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .keychainWriteFailed(let status):
      return "Unable to save Exa API key to Keychain (status \(status))."
    case .keychainDeleteFailed(let status):
      return "Unable to delete Exa API key from Keychain (status \(status))."
    }
  }
}
