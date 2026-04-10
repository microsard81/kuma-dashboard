import Foundation
import Security

// MARK: - Errors
enum KeychainError: Error, Equatable {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
}

// MARK: - Protocol
protocol KeychainStoreProtocol {
    func save(token: String, forKey key: String) throws
    func load(forKey key: String) throws -> String
    func delete(forKey key: String) throws
}

// MARK: - Implementation
final class KeychainStore: KeychainStoreProtocol {
    static let shared = KeychainStore()

    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.example.UptimeDashboard") {
        self.service = service
    }

    // MARK: - Save

    /// Saves a token to the Keychain for the given key.
    /// If an item already exists for that key, it is updated.
    /// The token is never written to logs or UserDefaults.
    func save(token: String, forKey key: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.unexpectedStatus(errSecParam)
        }

        // Try to update an existing item first
        let query = baseQuery(forKey: key)
        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // Item doesn't exist yet — insert it
            var insertQuery = baseQuery(forKey: key)
            insertQuery[kSecValueData] = data
            insertQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

            let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(insertStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    // MARK: - Load

    /// Loads a token from the Keychain for the given key.
    /// Throws `KeychainError.itemNotFound` if no item exists.
    func load(forKey key: String) throws -> String {
        var query = baseQuery(forKey: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedStatus(errSecDecode)
            }
            return token
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Delete

    /// Deletes the Keychain item for the given key.
    /// Does not throw if the item does not exist.
    func delete(forKey key: String) throws {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Private helpers

    private func baseQuery(forKey key: String) -> [CFString: Any] {
        return [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
    }
}
