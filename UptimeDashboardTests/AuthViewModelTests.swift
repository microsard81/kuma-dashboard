// Feature: ios-native-app, Property 2: Validazione input vuoti/whitespace
// Validates: Requirements 1.7

import XCTest
@testable import UptimeDashboard

// MARK: - MockNetworkClient

final class MockNetworkClient: NetworkClientProtocol {

    // Configurable responses
    var loginResult: Result<LoginResult, Error> = .success(.success)
    var verify2FAResult: Result<Bool, Error> = .success(true)
    var logoutError: Error? = nil

    // Call counters
    private(set) var loginCallCount = 0
    private(set) var verify2FACallCount = 0
    private(set) var logoutCallCount = 0

    func login(username: String, password: String) async throws -> LoginResult {
        loginCallCount += 1
        return try loginResult.get()
    }

    func verify2FA(code: String) async throws -> Bool {
        verify2FACallCount += 1
        return try verify2FAResult.get()
    }

    func enrollTOTP(code: String) async throws -> Bool { true }

    func changePassword(newPassword: String) async throws -> LoginResult { .success }

    func logout() async throws {
        logoutCallCount += 1
        if let error = logoutError { throw error }
    }

    func fetchDashboardData() async throws -> DashboardResponse {
        fatalError("Not used in AuthViewModel tests")
    }

    func subscribeAPNs(deviceToken: String, deviceId: String) async throws {
        fatalError("Not used in AuthViewModel tests")
    }

    func unsubscribeAPNs(deviceToken: String) async throws {
        fatalError("Not used in AuthViewModel tests")
    }

    func getBiometricToken() async throws -> String { return "mock_biometric_token" }
    func biometricLogin(username: String, biometricToken: String) async throws {}
    func fetchSensorData() async throws -> Data { return Data("{}".utf8) }
}

// MARK: - MockKeychainStore

final class MockKeychainStore: KeychainStoreProtocol {

    private var store: [String: String] = [:]

    private(set) var saveCallCount = 0
    private(set) var deleteCallCount = 0

    func save(token: String, forKey key: String) throws {
        saveCallCount += 1
        store[key] = token
    }

    func load(forKey key: String) throws -> String {
        guard let value = store[key] else { throw KeychainError.itemNotFound }
        return value
    }

    func delete(forKey key: String) throws {
        deleteCallCount += 1
        store.removeValue(forKey: key)
    }

    func contains(key: String) -> Bool {
        store[key] != nil
    }
}

// MARK: - Whitespace string generators

/// Returns a string composed entirely of whitespace characters.
private func randomWhitespaceString() -> String {
    let whitespaceChars: [Character] = [" ", "\t", "\n", "\r", "\r\n".first!, " "]
    let length = Int.random(in: 1...20)
    return String((0..<length).map { _ in whitespaceChars.randomElement()! })
}

// MARK: - AuthViewModelTests

final class AuthViewModelTests: XCTestCase {

    private var network: MockNetworkClient!
    private var keychain: MockKeychainStore!
    private var sut: AuthViewModel!

    @MainActor
    override func setUp() {
        super.setUp()
        network = MockNetworkClient()
        keychain = MockKeychainStore()
        sut = AuthViewModel(network: network, keychain: keychain)
    }

    override func tearDown() {
        sut = nil
        network = nil
        keychain = nil
        super.tearDown()
    }

    // MARK: - Property 2: Validazione input vuoti/whitespace
    // Feature: ios-native-app, Property 2: Validazione input vuoti/whitespace
    // Validates: Requirements 1.7

    func testWhitespaceRejected() async {
        // For any whitespace-only username or password, login must NOT call the network
        // and must set errorMessage.
        for i in 0..<100 {
            // Reset state
            await MainActor.run {
                sut = AuthViewModel(network: network, keychain: keychain)
                network.loginCallCount = 0
            }

            let whitespaceUser = randomWhitespaceString()
            let whitespacePass = randomWhitespaceString()

            // Test whitespace username with valid password
            await sut.login(username: whitespaceUser, password: "validPassword", rememberMe: false)
            XCTAssertEqual(network.loginCallCount, 0,
                "Iteration \(i): network.login must NOT be called for whitespace username")
            XCTAssertNotNil(sut.errorMessage,
                "Iteration \(i): errorMessage must be set for whitespace username")

            // Reset
            await MainActor.run { network.loginCallCount = 0 }

            // Test valid username with whitespace password
            await sut.login(username: "validUser", password: whitespacePass, rememberMe: false)
            XCTAssertEqual(network.loginCallCount, 0,
                "Iteration \(i): network.login must NOT be called for whitespace password")
            XCTAssertNotNil(sut.errorMessage,
                "Iteration \(i): errorMessage must be set for whitespace password")

            // Reset
            await MainActor.run { network.loginCallCount = 0 }

            // Test both whitespace
            await sut.login(username: whitespaceUser, password: whitespacePass, rememberMe: false)
            XCTAssertEqual(network.loginCallCount, 0,
                "Iteration \(i): network.login must NOT be called when both fields are whitespace")
            XCTAssertNotNil(sut.errorMessage,
                "Iteration \(i): errorMessage must be set when both fields are whitespace")
        }
    }

    // MARK: - Unit Tests

    // MARK: testLoginSuccess

    func testLoginSuccess() async {
        network.loginResult = .success(.success)

        await sut.login(username: "admin", password: "secret", rememberMe: false)

        XCTAssertEqual(sut.state, .authenticated)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(network.loginCallCount, 1)
    }

    // MARK: testLogin401_setsErrorMessage

    func testLogin401_setsErrorMessage() async {
        network.loginResult = .failure(NetworkError.unauthorized)

        await sut.login(username: "admin", password: "wrong", rememberMe: false)

        XCTAssertEqual(sut.state, .idle)
        XCTAssertNotNil(sut.errorMessage)
        // Req 1.3 — message must be generic, not reveal which field is wrong
        XCTAssertEqual(sut.errorMessage, "Credenziali non valide")
    }

    // MARK: testLoginRequires2FA_setsState

    func testLoginRequires2FA_setsState() async {
        network.loginResult = .success(.requires2FA)

        await sut.login(username: "admin", password: "secret", rememberMe: false)

        XCTAssertEqual(sut.state, .requires2FA)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: testVerify2FA_success

    func testVerify2FA_success() async {
        network.verify2FAResult = .success(true)

        await sut.verify2FA(code: "123456")

        XCTAssertEqual(sut.state, .authenticated)
        XCTAssertNil(sut.errorMessage)
        // Req 2.4 — session token must be saved in Keychain
        XCTAssertTrue(keychain.contains(key: "session_token"))
    }

    // MARK: testVerify2FA_error_setsErrorMessage

    func testVerify2FA_error_setsErrorMessage() async {
        network.verify2FAResult = .failure(NetworkError.unauthorized)

        await sut.verify2FA(code: "000000")

        XCTAssertNotEqual(sut.state, .authenticated)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertEqual(sut.errorMessage, "Codice non valido")
    }

    // MARK: testVerify2FA_returnsFalse_setsErrorMessage

    func testVerify2FA_returnsFalse_setsErrorMessage() async {
        network.verify2FAResult = .success(false)

        await sut.verify2FA(code: "000000")

        XCTAssertNotEqual(sut.state, .authenticated)
        XCTAssertEqual(sut.errorMessage, "Codice non valido")
    }

    // MARK: testLogout_clearsState

    func testLogout_clearsState() async {
        // First authenticate
        network.loginResult = .success(.success)
        await sut.login(username: "admin", password: "secret", rememberMe: false)
        XCTAssertEqual(sut.state, .authenticated)

        // Save a token to verify it gets deleted
        try? keychain.save(token: "active", forKey: "session_token")

        await sut.logout()

        XCTAssertEqual(sut.state, .unauthenticated)
        XCTAssertFalse(keychain.contains(key: "session_token"),
            "session_token must be removed from Keychain on logout")
        XCTAssertEqual(network.logoutCallCount, 1)
    }

    // MARK: testLogout_withNetworkError_stillClearsState

    func testLogout_withNetworkError_stillClearsState() async {
        // Req 11.4 — logout must clear state even if network call fails
        network.logoutError = NetworkError.networkError(URLError(.notConnectedToInternet))
        try? keychain.save(token: "active", forKey: "session_token")

        await sut.logout()

        XCTAssertEqual(sut.state, .unauthenticated)
        XCTAssertFalse(keychain.contains(key: "session_token"))
    }

    // MARK: testSessionExpired_triggersLogout

    func testSessionExpired_triggersLogout() async throws {
        // Simulate an authenticated state
        network.loginResult = .success(.success)
        await sut.login(username: "admin", password: "secret", rememberMe: false)
        try? keychain.save(token: "active", forKey: "session_token")
        XCTAssertEqual(sut.state, .authenticated)

        // Post the sessionExpired notification (as NetworkClient would)
        NotificationCenter.default.post(name: Notification.Name("sessionExpired"), object: nil)

        // Allow the async logout task to complete
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(sut.state, .unauthenticated,
            "sessionExpired notification must trigger automatic logout")
        XCTAssertFalse(keychain.contains(key: "session_token"),
            "session_token must be removed from Keychain on session expiry")
    }

    // MARK: testEmptyUsername_preventsNetworkCall

    func testEmptyUsername_preventsNetworkCall() async {
        await sut.login(username: "", password: "secret", rememberMe: false)

        XCTAssertEqual(network.loginCallCount, 0)
        XCTAssertNotNil(sut.errorMessage)
    }

    // MARK: testEmptyPassword_preventsNetworkCall

    func testEmptyPassword_preventsNetworkCall() async {
        await sut.login(username: "admin", password: "", rememberMe: false)

        XCTAssertEqual(network.loginCallCount, 0)
        XCTAssertNotNil(sut.errorMessage)
    }
}
