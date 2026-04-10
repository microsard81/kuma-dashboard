// Feature: ios-native-app
// Requisiti: 1.2, 1.3, 1.4, 1.7, 2.2, 2.3, 2.4, 11.2, 11.3, 11.4

import Foundation
import Combine
import LocalAuthentication

// MARK: - AuthState

enum AuthState: Equatable {
    case idle
    case requires2FA
    case requiresTOTPSetup(secret: String, uri: String)
    case requiresPasswordChange
    case authenticated
    case unauthenticated
}

// MARK: - AuthViewModel

@MainActor
final class AuthViewModel: ObservableObject {

    @Published var state: AuthState = .idle
    @Published var errorMessage: String? = nil
    @Published var isLoading: Bool = false

    private let network: NetworkClientProtocol
    private let keychain: KeychainStoreProtocol
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(network: NetworkClientProtocol, keychain: KeychainStoreProtocol) {
        self.network = network
        self.keychain = keychain
        subscribeToSessionExpired()
        // Mostra BiometricGateView SOLO se c'è un token biometrico salvato
        // (significa che l'utente ha già fatto almeno un login completo con 2FA)
        let hasBiometricToken = (try? keychain.load(forKey: "biometric_token")) != nil
        state = hasBiometricToken ? .idle : .unauthenticated
    }

    func authenticateWithBiometrics() async {
        let context = LAContext()
        var error: NSError? = nil

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            state = .unauthenticated
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Accedi a INVA Dashboard"
            )
            guard success else {
                state = .unauthenticated
                return
            }

            // Face ID OK — usa il token biometrico per il login senza password né 2FA
            guard let username = try? keychain.load(forKey: "saved_username"),
                  let biometricToken = try? keychain.load(forKey: "biometric_token") else {
                state = .unauthenticated
                return
            }

            isLoading = true
            defer { isLoading = false }

            do {
                try await network.biometricLogin(username: username, biometricToken: biometricToken)
                try? keychain.save(token: "active", forKey: "session_token")
                state = .authenticated
            } catch {
                // Token scaduto o non valido — vai al login manuale
                try? keychain.delete(forKey: "biometric_token")
                try? keychain.delete(forKey: "session_token")
                state = .unauthenticated
            }
        } catch {
            state = .unauthenticated
        }
    }

    // MARK: - login

    /// Validates credentials and initiates the login flow.
    /// Username and password are never written to logs.
    func login(username: String, password: String, rememberMe: Bool) async {
        let trimmedUser = username.trimmingCharacters(in: .whitespaces)
        let trimmedPass = password.trimmingCharacters(in: .whitespaces)

        guard !trimmedUser.isEmpty, !trimmedPass.isEmpty else {
            errorMessage = "Inserisci username e password"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await network.login(username: username, password: password)
            switch result {
            case .requires2FA:
                if rememberMe {
                    try? keychain.save(token: trimmedUser, forKey: "saved_username")
                    try? keychain.save(token: trimmedPass, forKey: "saved_password")
                }
                state = .requires2FA
            case .requiresTOTPSetup(let secret, let uri):
                if rememberMe {
                    try? keychain.save(token: trimmedUser, forKey: "saved_username")
                    try? keychain.save(token: trimmedPass, forKey: "saved_password")
                }
                state = .requiresTOTPSetup(secret: secret, uri: uri)
            case .requiresPasswordChange:
                state = .requiresPasswordChange
            case .success:
                if rememberMe {
                    try? keychain.save(token: trimmedUser, forKey: "saved_username")
                    try? keychain.save(token: trimmedPass, forKey: "saved_password")
                }
                state = .authenticated
            }
        } catch NetworkError.unauthorized {
            errorMessage = "Credenziali non valide"
        } catch {
            errorMessage = "Errore di connessione"
        }
    }

    // MARK: - changePassword

    /// Changes the password when forced by the server.
    func changePassword(newPassword: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await network.changePassword(newPassword: newPassword)
            switch result {
            case .requires2FA:
                state = .requires2FA
            case .requiresTOTPSetup(let secret, let uri):
                state = .requiresTOTPSetup(secret: secret, uri: uri)
            case .requiresPasswordChange:
                errorMessage = "Errore imprevisto"
            case .success:
                state = .authenticated
            }
        } catch NetworkError.validationError(let message) {
            errorMessage = message
        } catch NetworkError.invalidResponse(statusCode: 400) {
            errorMessage = "La password non rispetta i requisiti di complessità"
        } catch {
            errorMessage = "Errore di connessione"
        }
    }

    // MARK: - enrollTOTP

    /// Completes TOTP enrollment by verifying the first code.
    func enrollTOTP(code: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let success = try await network.enrollTOTP(code: code)
            if success {
                try? keychain.save(token: "active", forKey: "session_token")
                if let networkClient = network as? NetworkClient,
                   let token = networkClient._pendingBiometricToken,
                   let username = networkClient._pendingUsername {
                    try? keychain.save(token: token, forKey: "biometric_token")
                    try? keychain.save(token: username, forKey: "saved_username")
                    networkClient._pendingBiometricToken = nil
                    networkClient._pendingUsername = nil
                }
                state = .authenticated
            } else {
                errorMessage = "Codice non valido. Riprova."
            }
        } catch {
            errorMessage = "Codice non valido"
        }
    }

    // MARK: - verify2FA

    /// Submits the TOTP code. On success, persists the session marker in Keychain.
    /// The code is never written to logs.
    func verify2FA(code: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let success = try await network.verify2FA(code: code)
            if success {
                try? keychain.save(token: "active", forKey: "session_token")
                // Il token biometrico è già nella risposta /api/2fa — leggilo dal NetworkClient
                if let networkClient = network as? NetworkClient,
                   let token = networkClient._pendingBiometricToken,
                   let username = networkClient._pendingUsername {
                    try? keychain.save(token: token, forKey: "biometric_token")
                    try? keychain.save(token: username, forKey: "saved_username")
                    networkClient._pendingBiometricToken = nil
                    networkClient._pendingUsername = nil
                }
                state = .authenticated
            } else {
                errorMessage = "Codice non valido"
            }
        } catch {
            errorMessage = "Codice non valido"
        }
    }

    // MARK: - logout

    /// Calls the backend logout endpoint (errors ignored), clears Keychain, and resets state.
    func logout() async {
        try? await network.logout()
        try? keychain.delete(forKey: "session_token")
        try? keychain.delete(forKey: "flask_session_cookies")
        try? keychain.delete(forKey: "saved_username")
        try? keychain.delete(forKey: "saved_password")
        try? keychain.delete(forKey: "biometric_token")
        if let networkClient = network as? NetworkClient,
           let cookies = HTTPCookieStorage.shared.cookies(for: networkClient.baseURL) {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
        state = .unauthenticated
    }

    // MARK: - Session expiry

    /// Subscribes to the `sessionExpired` notification posted by NetworkClient
    /// when a 302 → /login redirect is detected.
    private func subscribeToSessionExpired() {
        NotificationCenter.default
            .publisher(for: Notification.Name("sessionExpired"))
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.logout() }
            }
            .store(in: &cancellables)
    }
}
