// Feature: ios-native-app, Property 1: Round-trip Keychain del Session_Token
// Validates: Requirements 1.5, 2.4, 12.1, 12.2

import XCTest
@testable import UptimeDashboard

// MARK: - ASCII token generator helper
private func randomASCIIString(length: Int) -> String {
    // Printable ASCII range: 0x21 ('!') to 0x7E ('~'), excluding characters
    // that could cause JSON/encoding issues. We use alphanumeric + common symbols.
    let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:,.<>?"
    return String((0..<length).map { _ in chars.randomElement()! })
}

final class KeychainStoreTests: XCTestCase {

    // Use a dedicated test service to avoid polluting the real Keychain
    private var store: KeychainStore!

    override func setUp() {
        super.setUp()
        store = KeychainStore(service: "com.example.UptimeDashboard.tests")
    }

    override func tearDown() {
        // Best-effort cleanup: delete any keys that might have been left behind
        super.tearDown()
    }

    // MARK: - Property 1: Round-trip Keychain del Session_Token
    // Validates: Requirements 1.5, 2.4, 12.1

    func testTokenRoundTripProperty() throws {
        // For any valid session token string (ASCII, length 8-128),
        // saving to Keychain and loading must return the identical value.
        for i in 0..<100 {
            let length = Int.random(in: 8...128)
            let token = randomASCIIString(length: length)
            let key = "roundtrip-\(UUID().uuidString)"

            defer {
                // Clean up after each iteration
                try? store.delete(forKey: key)
            }

            try store.save(token: token, forKey: key)
            let loaded = try store.load(forKey: key)

            XCTAssertEqual(loaded, token,
                "Round-trip failed at iteration \(i): token of length \(length) was not preserved")
        }
    }

    // MARK: - Unit Tests

    func testSaveAndLoad() throws {
        let key = UUID().uuidString
        let token = "test-session-token-abc123"
        defer { try? store.delete(forKey: key) }

        try store.save(token: token, forKey: key)
        let loaded = try store.load(forKey: key)

        XCTAssertEqual(loaded, token)
    }

    func testDelete() throws {
        let key = UUID().uuidString
        let token = "token-to-delete"

        try store.save(token: token, forKey: key)
        try store.delete(forKey: key)

        XCTAssertThrowsError(try store.load(forKey: key)) { error in
            XCTAssertEqual(error as? KeychainError, KeychainError.itemNotFound,
                "Expected itemNotFound after deletion")
        }
    }

    func testOverwrite() throws {
        let key = UUID().uuidString
        let firstToken = "first-token-value"
        let secondToken = "second-token-value"
        defer { try? store.delete(forKey: key) }

        try store.save(token: firstToken, forKey: key)
        try store.save(token: secondToken, forKey: key)

        let loaded = try store.load(forKey: key)
        XCTAssertEqual(loaded, secondToken,
            "Second save must overwrite the first value")
        XCTAssertNotEqual(loaded, firstToken,
            "First value must no longer be present after overwrite")
    }

    func testLoadNonExistent() {
        let key = UUID().uuidString

        XCTAssertThrowsError(try store.load(forKey: key)) { error in
            XCTAssertEqual(error as? KeychainError, KeychainError.itemNotFound,
                "Loading a non-existent key must throw itemNotFound")
        }
    }

    func testDeleteNonExistentDoesNotThrow() {
        // Deleting a key that doesn't exist must not throw
        let key = UUID().uuidString
        XCTAssertNoThrow(try store.delete(forKey: key))
    }

    func testSaveEmptyStringToken() throws {
        // Edge case: empty string is a valid token value
        let key = UUID().uuidString
        defer { try? store.delete(forKey: key) }

        try store.save(token: "", forKey: key)
        let loaded = try store.load(forKey: key)
        XCTAssertEqual(loaded, "")
    }

    func testMultipleKeysAreIndependent() throws {
        let key1 = UUID().uuidString
        let key2 = UUID().uuidString
        let token1 = "token-for-key1"
        let token2 = "token-for-key2"
        defer {
            try? store.delete(forKey: key1)
            try? store.delete(forKey: key2)
        }

        try store.save(token: token1, forKey: key1)
        try store.save(token: token2, forKey: key2)

        XCTAssertEqual(try store.load(forKey: key1), token1)
        XCTAssertEqual(try store.load(forKey: key2), token2)
    }
}
