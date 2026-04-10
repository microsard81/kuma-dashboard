// Feature: ios-native-app
// Validates: Requirements 9.1, 9.2, 9.4, 9.5, 9.6, 9.7

import XCTest
@testable import UptimeDashboard

// MARK: - MockNetworkClient

/// Minimal mock of NetworkClientProtocol for NotificationManager tests.
final class MockNetworkClient: NetworkClientProtocol {

    // Recorded calls
    var subscribeAPNsCalls: [(deviceToken: String, deviceId: String)] = []
    var unsubscribeAPNsCalls: [String] = []

    // Configurable behaviour
    var subscribeError: Error?
    var unsubscribeError: Error?

    func login(username: String, password: String) async throws -> LoginResult { .success }
    func verify2FA(code: String) async throws -> Bool { true }
    func enrollTOTP(code: String) async throws -> Bool { true }
    func logout() async throws {}
    func fetchDashboardData() async throws -> DashboardResponse {
        throw NetworkError.networkError(URLError(.unknown))
    }

    func subscribeAPNs(deviceToken: String, deviceId: String) async throws {
        subscribeAPNsCalls.append((deviceToken: deviceToken, deviceId: deviceId))
        if let error = subscribeError { throw error }
    }

    func unsubscribeAPNs(deviceToken: String) async throws {
        unsubscribeAPNsCalls.append(deviceToken)
        if let error = unsubscribeError { throw error }
    }

    func getBiometricToken() async throws -> String { return "mock_biometric_token" }
    func biometricLogin(username: String, biometricToken: String) async throws {}
}

// MARK: - NotificationManagerTests

final class NotificationManagerTests: XCTestCase {

    // Each test gets its own isolated UserDefaults suite so tests don't interfere.
    private func makeManager(network: MockNetworkClient) -> NotificationManager {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        return NotificationManager(network: network, defaults: defaults)
    }

    // MARK: - testTokenConversion_dataToHex

    func testTokenConversion_dataToHex() async {
        // Verifies that a known Data value is converted to the expected hex string.
        let network = MockNetworkClient()
        let manager = makeManager(network: network)

        // 4 bytes → "deadbeef"
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        await manager.handleTokenUpdate(deviceToken: data)

        XCTAssertEqual(network.subscribeAPNsCalls.first?.deviceToken, "deadbeef")
    }

    // MARK: - testHandleTokenUpdate_success_callsSubscribeAPNs

    func testHandleTokenUpdate_success_callsSubscribeAPNs() async {
        // subscribeAPNs must be called with the correct hex token.
        let network = MockNetworkClient()
        let manager = makeManager(network: network)

        let bytes: [UInt8] = (0..<32).map { UInt8($0) }
        let data = Data(bytes)
        let expectedHex = bytes.map { String(format: "%02x", $0) }.joined()

        await manager.handleTokenUpdate(deviceToken: data)

        XCTAssertEqual(network.subscribeAPNsCalls.count, 1)
        XCTAssertEqual(network.subscribeAPNsCalls[0].deviceToken, expectedHex)
    }

    // MARK: - testHandleTokenUpdate_networkError_setsPendingFlag

    func testHandleTokenUpdate_networkError_setsPendingFlag() async {
        // When subscribeAPNs throws, pendingAPNsRegistration must be set to true.
        let network = MockNetworkClient()
        network.subscribeError = NetworkError.networkError(URLError(.notConnectedToInternet))

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let manager = NotificationManager(network: network, defaults: defaults)

        let data = Data([0x01, 0x02, 0x03, 0x04])
        await manager.handleTokenUpdate(deviceToken: data)

        XCTAssertTrue(defaults.bool(forKey: "pendingAPNsRegistration"))
    }

    // MARK: - testHandleTokenUpdate_success_clearsPendingFlag

    func testHandleTokenUpdate_success_clearsPendingFlag() async {
        // After a successful subscribe, pendingAPNsRegistration must be false.
        let network = MockNetworkClient()

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        // Pre-set the flag to true to simulate a previous failure.
        defaults.set(true, forKey: "pendingAPNsRegistration")

        let manager = NotificationManager(network: network, defaults: defaults)

        let data = Data([0xAA, 0xBB, 0xCC, 0xDD])
        await manager.handleTokenUpdate(deviceToken: data)

        XCTAssertFalse(defaults.bool(forKey: "pendingAPNsRegistration"))
    }

    // MARK: - testUnregister_callsUnsubscribeAPNs

    func testUnregister_callsUnsubscribeAPNs() async throws {
        // unsubscribeAPNs must be called with the token previously stored in UserDefaults.
        let network = MockNetworkClient()

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let storedToken = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"
        defaults.set(storedToken, forKey: "apnsDeviceToken")

        let manager = NotificationManager(network: network, defaults: defaults)

        try await manager.unregister()

        XCTAssertEqual(network.unsubscribeAPNsCalls.count, 1)
        XCTAssertEqual(network.unsubscribeAPNsCalls[0], storedToken)
        // Token must be removed from UserDefaults after unregister
        XCTAssertNil(defaults.string(forKey: "apnsDeviceToken"))
    }

    // MARK: - testUnregister_noToken_doesNotCallUnsubscribe

    func testUnregister_noToken_doesNotCallUnsubscribe() async throws {
        // If no token is stored, unsubscribeAPNs must not be called.
        let network = MockNetworkClient()
        let manager = makeManager(network: network)

        try await manager.unregister()

        XCTAssertTrue(network.unsubscribeAPNsCalls.isEmpty)
    }
}
