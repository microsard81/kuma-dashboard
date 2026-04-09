// Feature: ios-native-app
// Requisiti: 2.1, 2.5, 2.6, 11.2

import SwiftUI

struct TwoFAView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var code: String = ""

    /// The verify button is enabled only when the code is exactly 6 digits (Req 2.1).
    private var isCodeValid: Bool {
        code.count == 6 && code.allSatisfy(\.isNumber)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#141c2b")
                    .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // MARK: - Title
                Text("Verifica in due passaggi")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                Text("Inserisci il codice a 6 cifre dalla tua app di autenticazione.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // MARK: - Code input
                // Req 2.1 — numeric field; Req 2.5 — autocompletamento da SMS/app autenticazione
                TextField("Codice TOTP", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.title.monospacedDigit())
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .onChange(of: code) { newValue in
                        // Enforce max 6 digits, strip non-numeric characters
                        let filtered = String(newValue.filter(\.isNumber).prefix(6))
                        if filtered != newValue { code = filtered }
                    }
                    .accessibilityLabel("Codice TOTP a 6 cifre")

                // MARK: - Error message
                if let errorMessage = authViewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .accessibilityLabel("Errore: \(errorMessage)")
                }

                // MARK: - Verify button
                Button {
                    Task {
                        await authViewModel.verify2FA(code: code)
                    }
                } label: {
                    Group {
                        if authViewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Verifica")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isCodeValid ? Color.accentColor : Color.gray)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }
                // Disabled until exactly 6 digits are entered
                .disabled(!isCodeValid || authViewModel.isLoading)
                .padding(.horizontal)
                .accessibilityLabel("Verifica")
                .accessibilityHint(isCodeValid ? "" : "Inserisci un codice a 6 cifre per abilitare il pulsante")

                Spacer()
            }
            .navigationTitle("Autenticazione")
            .navigationBarTitleDisplayMode(.inline)
            } // ZStack
        }
    }
}

#if DEBUG
#Preview {
    TwoFAView()
        .environmentObject(AuthViewModel(
            network: Preview2FANetworkClient(),
            keychain: Preview2FAKeychainStore()
        ))
}

private final class Preview2FANetworkClient: NetworkClientProtocol {
    func login(username: String, password: String) async throws -> LoginResult { .success }
    func verify2FA(code: String) async throws -> Bool { true }
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

private final class Preview2FAKeychainStore: KeychainStoreProtocol {
    func save(token: String, forKey key: String) throws {}
    func load(forKey key: String) throws -> String { "" }
    func delete(forKey key: String) throws {}
}
#endif
