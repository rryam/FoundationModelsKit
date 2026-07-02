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
  private let keychain: ExaAPIKeychain

  public init(
    service: String = "com.rryam.FoundationModelsTools.exa",
    account: String = "apiKey",
    legacyUserDefaults: UserDefaults = .standard
  ) {
    self.init(
      service: service,
      account: account,
      legacyUserDefaults: legacyUserDefaults,
      keychain: .live
    )
  }

  init(
    service: String,
    account: String,
    legacyUserDefaults: UserDefaults,
    keychain: ExaAPIKeychain
  ) {
    self.service = service
    self.account = account
    self.legacyUserDefaults = legacyUserDefaults
    self.keychain = keychain
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
      return legacyKey
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
    let updateStatus = keychain.update(query, encodedKey)

    switch updateStatus {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      let addStatus = keychain.add(query, encodedKey)
      guard addStatus == errSecSuccess else {
        throw ExaAPIKeyStoreError.keychainWriteFailed(addStatus)
      }
    default:
      throw ExaAPIKeyStoreError.keychainWriteFailed(updateStatus)
    }
  }

  public func deleteAPIKey() throws {
    let status = keychain.delete(query)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw ExaAPIKeyStoreError.keychainDeleteFailed(status)
    }
  }

  private func keychainAPIKey() -> String? {
    var lookup = query
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne

    let result = keychain.copyMatching(lookup)
    guard result.status == errSecSuccess, let data = result.data else {
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

struct ExaAPIKeychain: @unchecked Sendable {
  var copyMatching: @Sendable ([String: Any]) -> (status: OSStatus, data: Data?)
  var update: @Sendable ([String: Any], Data) -> OSStatus
  var add: @Sendable ([String: Any], Data) -> OSStatus
  var delete: @Sendable ([String: Any]) -> OSStatus

  static let live = ExaAPIKeychain(
    copyMatching: { query in
      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      return (status, item as? Data)
    },
    update: { query, data in
      SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
    },
    add: { query, data in
      var attributes = query
      attributes[kSecValueData as String] = data
      return SecItemAdd(attributes as CFDictionary, nil)
    },
    delete: { query in
      SecItemDelete(query as CFDictionary)
    }
  )
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
