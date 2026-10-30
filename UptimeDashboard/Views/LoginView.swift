// Feature: ios-native-app
// Requisiti: 1.1, 1.5, 1.7, 11.2

import SwiftUI
import LocalAuthentication

struct LoginView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var rememberMe: Bool = false
    @State private var showForgotPassword = false

    private var isFormValid: Bool {
        !username.isEmpty && !password.isEmpty
    }

    /// Controlla se c'è un token biometrico salvato, la biometria è disponibile e la preferenza è attiva
    private var canUseBiometrics: Bool {
        guard settingsVM.biometricEnabled else { return false }
        let context = LAContext()
        var error: NSError? = nil
        let hasBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let hasBiometricToken = (try? KeychainStore.shared.load(forKey: "biometric_token")) != nil
        return hasBiometrics && hasBiometricToken
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#141c2b")
                    .ignoresSafeArea()

            ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)

                Text("INVA Dashboard")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 16) {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()
                        .foregroundColor(.primary)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .foregroundColor(.primary)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                    Toggle("Ricordami", isOn: $rememberMe)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal)

                if let errorMessage = authViewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task {
                        await authViewModel.login(
                            username: username,
                            password: password,
                            rememberMe: rememberMe
                        )
                    }
                } label: {
                    Group {
                        if authViewModel.isLoading {
                            ProgressView().progressViewStyle(.circular).tint(.white)
                        } else {
                            Text("Accedi").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isFormValid ? Color.accentColor : Color.gray)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }
                .disabled(!isFormValid || authViewModel.isLoading)
                .padding(.horizontal)

                Button("Password dimenticata?") {
                    showForgotPassword = true
                }
                .font(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                // Pulsante Face ID / Touch ID — visibile solo se c'è una sessione salvata
                if canUseBiometrics {
                    Button {
                        Task { await authViewModel.authenticateWithBiometrics() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: biometricIcon)
                                .font(.title2)
                            Text("Accedi con \(biometricLabel)")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 20)
            }
            .foregroundStyle(.white)
            } // ScrollView
            .navigationBarHidden(true)
            } // ZStack
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordSheet(initialUsername: username)
                    .environmentObject(authViewModel)
            }
        }
    }

    private var biometricIcon: String {
        let context = LAContext()
        var error: NSError? = nil
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "faceid"
        }
        return context.biometryType == .faceID ? "faceid" : "touchid"
    }

    private var biometricLabel: String {
        let context = LAContext()
        var error: NSError? = nil
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "Face ID"
        }
        return context.biometryType == .faceID ? "Face ID" : "Touch ID"
    }
}

// MARK: - ForgotPasswordSheet

/// Sheet nativo per richiedere il link di reset password via email.
private struct ForgotPasswordSheet: View {

    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username: String
    @State private var isSending = false
    @State private var outcome: PasswordResetOutcome?

    init(initialUsername: String) {
        _username = State(initialValue: initialUsername)
    }

    private var isSent: Bool {
        if case .sent = outcome { return true }
        return false
    }

    private var canSend: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !isSent
    }

    var body: some View {
        ZStack {
            // Stesso sfondo della schermata di login
            Color(hex: "#141c2b")
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header: titolo + Chiudi
                    HStack {
                        Text("Password dimenticata")
                            .font(.title3.bold())
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Chiudi") { dismiss() }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.top, 24)

                    Text("Inserisci il tuo username. Riceverai via email un link valido 30 minuti. Dopo il reset il 2FA verrà reimpostato e sarai disconnesso da tutti i dispositivi.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Campo identico a quello del login
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()
                        .foregroundColor(.primary)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .disabled(isSent)

                    if let outcome {
                        switch outcome {
                        case .sent(let message):
                            Label(message, systemImage: "envelope.badge")
                                .font(.footnote)
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .failed(let message):
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Pulsante pieno, stesso stile di "Accedi".
                    // Sempre attivo (aspetto stabile mentre si digita): senza
                    // username non invia e mostra un messaggio.
                    Button {
                        sendResetLink()
                    } label: {
                        Group {
                            if isSending {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                            } else {
                                Text(isSent ? "Link inviato" : "Invia link").fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isSending || isSent)

                    if isSent {
                        Button("Torna al login") { dismiss() }
                            .font(.footnote)
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal)
                .foregroundStyle(.white)
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Invia la richiesta di reset; se lo username è vuoto non chiama il backend.
    private func sendResetLink() {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            outcome = .failed("Inserisci lo username")
            return
        }
        guard !isSending, !isSent else { return }
        Task {
            isSending = true
            outcome = await authViewModel.requestPasswordReset(username: trimmed)
            isSending = false
        }
    }
}

#if DEBUG
#Preview {
    LoginView()
        .environmentObject(AuthViewModel(
            network: PreviewNetworkClient(),
            keychain: PreviewKeychainStore()
        ))
        .environmentObject(SettingsViewModel())
}

private final class PreviewNetworkClient: NetworkClientProtocol {
    func login(username: String, password: String) async throws -> LoginResult { .success }
    func changePassword(newPassword: String) async throws -> LoginResult { .success }
    func verify2FA(code: String) async throws -> Bool { true }
    func enrollTOTP(code: String) async throws -> Bool { true }
    func logout() async throws {}
    func fetchDashboardData() async throws -> DashboardResponse {
        let json = #"{"items":[],"global_state":"GREEN","timestamp":""}"#
        return try JSONDecoder().decode(DashboardResponse.self, from: Data(json.utf8))
    }
    func subscribeAPNs(deviceToken: String, deviceId: String) async throws {}
    func unsubscribeAPNs(deviceToken: String) async throws {}
    func getBiometricToken() async throws -> String { return "mock_token" }
    func biometricLogin(username: String, biometricToken: String) async throws {}
    func fetchSensorData() async throws -> Data { return Data("{}".utf8) }
    func fetchProbeHealth() async throws -> ProbeHealthResponse { ProbeHealthResponse(status: .ok, probes: []) }
    func requestPasswordReset(username: String) async throws -> String { "ok" }
}

private final class PreviewKeychainStore: KeychainStoreProtocol {
    func save(token: String, forKey key: String) throws {}
    func load(forKey key: String) throws -> String { "" }
    func delete(forKey key: String) throws {}
}
#endif
