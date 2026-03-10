//
//  KeychainManager.swift
//  MeetingMind
//
//  Created by Chris Cardinal on 2/3/26.
//

import Foundation
import Security

/// Secure storage for API keys using macOS Keychain
class KeychainManager {
    static let shared = KeychainManager()

    private let serviceName = "com.meetingmind.apikeys"

    enum KeyType: String {
        case deepgram = "deepgram_api_key"
        case claude = "claude_api_key"
    }

    private init() {}

    /// Save an API key to the Keychain
    func save(key: String, type: KeyType) -> Bool {
        // Delete existing key first
        delete(type: type)

        guard let data = key.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: type.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve an API key from the Keychain
    func get(type: KeyType) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: type.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    /// Delete an API key from the Keychain
    @discardableResult
    func delete(type: KeyType) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: type.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Check if an API key exists
    func exists(type: KeyType) -> Bool {
        return get(type: type) != nil
    }
}
