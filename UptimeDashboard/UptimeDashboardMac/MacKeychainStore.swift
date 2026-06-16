import Foundation
import Security
import LocalAuthentication

// MARK: - MacKeychainStore

/// Keychain wrapper with biometric access control for the Mac biometric token.
/// Uses service identifier: "com.inva.uptimeDashboard.mac.biometricToken"
///
/// Security:
/// - Token stored with `.biometryCurrentSet` — invalidated if biometric enrollment changes
/// - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — inaccessible when device locked
/// - Never logs token values or credentials
final class MacKeychainStore {

    enum KeychainKey: String {
        case biometricToken = "biometric_token"
        case tokenCreationDate = "token_creation_date"
    }

    enum KeychainError: Error {
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)
        case deleteFailed(OSStatus)
        case accessControlCreationFailed
        case dataConversionFailed
        case itemNotFound
        case dateParsingFailed
    }

    private let service = "com.inva.uptimeDashboard.mac.biometricToken"

    // MARK: - Save Token

    /// Saves token with biometric access control (.biometryCurrentSet).
    /// Username is stored as kSecAttrAccount for single-query retrieval.
    /// Handles duplicate items by deleting and re-adding (access control requires this pattern).
    func saveToken(_ token: String, forUsername username: String) throws {
        guard let tokenData = token.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        // Create biometric access control
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw KeychainError.accessControlCreationFailed
        }

        // Delete existing item first (SecItemUpdate doesn't work well with access control changes)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecValueData as String: tokenData,
            kSecAttrAccessControl as String: accessControl
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Save Creation Date

    /// Saves the token creation date as an ISO 8601 string.
    /// Uses `"{username}_creation_date"` as account key.
    /// Does NOT use biometric access control (no sensitive data).
    func saveCreationDate(_ date: Date, forUsername username: String) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let dateString = formatter.string(from: date)

        guard let dateData = dateString.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        let account = "\(username)_creation_date"

        // Try to update existing item first
        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: dateData
        ]

        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist, add it
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: dateData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
        } else if updateStatus == errSecDuplicateItem {
            // Shouldn't happen after update, but handle defensively: delete + add
            SecItemDelete(searchQuery as CFDictionary)

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: dateData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.saveFailed(updateStatus)
        }
    }

    // MARK: - Load Token

    /// Loads the biometric token. Triggers system biometric prompt via access control.
    /// Returns (username, token) tuple.
    func loadToken() throws -> (username: String, token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let item = result as? [String: Any],
              let tokenData = item[kSecValueData as String] as? Data,
              let token = String(data: tokenData, encoding: .utf8),
              let username = item[kSecAttrAccount as String] as? String else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.loadFailed(status)
        }

        // Skip creation date entries (account ends with "_creation_date")
        if username.hasSuffix("_creation_date") {
            throw KeychainError.itemNotFound
        }

        return (username: username, token: token)
    }

    // MARK: - Load Creation Date

    /// Loads the token creation date without biometric prompt.
    func loadCreationDate(forUsername username: String) throws -> Date {
        let account = "\(username)_creation_date"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let dateData = result as? Data,
              let dateString = String(data: dateData, encoding: .utf8) else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.loadFailed(status)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        guard let date = formatter.date(from: dateString) else {
            throw KeychainError.dateParsingFailed
        }

        return date
    }

    // MARK: - Has Token

    /// Checks if a token entry exists without triggering biometric prompt.
    /// Searches all items for the service and returns true if any is NOT a creation_date entry.
    func hasToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecInteractionNotAllowed {
            // At least one item requires biometric — that's our token
            return true
        }

        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return false
        }

        // Check if any item is NOT a creation_date entry
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               !account.hasSuffix("_creation_date") {
                return true
            }
        }

        return false
    }

    // MARK: - Delete All

    /// Deletes token and creation date entries for this service.
    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
