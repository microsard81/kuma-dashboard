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
}

private final class PreviewKeychainStore: KeychainStoreProtocol {
    func save(token: String, forKey key: String) throws {}
    func load(forKey key: String) throws -> String { "" }
    func delete(forKey key: String) throws {}
}
#endif
