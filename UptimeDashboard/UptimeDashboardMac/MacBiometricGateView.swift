import SwiftUI

/// Biometric unlock screen displayed when a stored token exists.
/// Auto-triggers LAContext on appear; shows retry + fallback buttons on failure.
///
/// Requirements: 3.1, 3.2, 3.5, 3.7, 4.1, 4.2, 4.3, 4.4, 4.5, 8.3, 8.4, 8.5
struct MacBiometricGateView: View {
    @EnvironmentObject var viewModel: MacAppViewModel

    // MARK: - State

    @State private var showRetryButton: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var retryCount: Int = 0

    // MARK: - Constants

    private let maxRetries = 3

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            // App name
            Text("INVA Dashboard")
                .font(.largeTitle.bold())

            // Status message
            Text(statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Biometric method icon
            Image(systemName: biometricIconName)
                .font(.system(size: 36))
                .foregroundColor(.accentColor)
                .padding(.top, 8)

            // Loading indicator OR buttons
            if viewModel.biometricManager.isAuthenticating {
                ProgressView()
                    .controlSize(.regular)
                    .padding(.top, 8)
            } else if showRetryButton {
                VStack(spacing: 12) {
                    // Error message
                    if showError, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Retry button with biometric icon
                    Button {
                        retryAuthentication()
                    } label: {
                        Label("Riprova", systemImage: biometricIconName)
                    }
                    .buttonStyle(.borderedProminent)

                    // Fallback to username/password
                    Button {
                        viewModel.authState = .login
                    } label: {
                        Text("Usa username e password")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 300, minHeight: 400)
        .onAppear {
            triggerInitialAuthentication()
        }
    }

    // MARK: - Computed Properties

    /// Status message changes based on current state.
    private var statusMessage: String {
        if viewModel.biometricManager.isAuthenticating {
            return "Autenticazione in corso..."
        } else if showError {
            return errorMessage
        } else {
            return "Autenticazione in corso..."
        }
    }

    /// SF Symbol icon based on available biometric method.
    /// - `.touchID` → "touchid"
    /// - `.appleWatch` → "applewatch"
    /// - `.both` → "lock.shield"
    /// - `.none` → "lock.shield" (fallback)
    private var biometricIconName: String {
        switch viewModel.biometricManager.availableMethod {
        case .touchID:
            return "touchid"
        case .appleWatch:
            return "applewatch"
        case .both:
            return "lock.shield"
        case .none:
            return "lock.shield"
        }
    }

    // MARK: - Actions

    /// Auto-triggers biometric authentication 500ms after view appears.
    private func triggerInitialAuthentication() {
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
            await performAuthentication()
        }
    }

    /// Retry button action: re-triggers authentication and tracks retry count.
    private func retryAuthentication() {
        retryCount += 1
        showRetryButton = false
        showError = false
        errorMessage = ""

        Task {
            await performAuthentication()
        }
    }

    /// Calls viewModel.authenticateWithBiometrics() and handles the result.
    private func performAuthentication() async {
        let result = await viewModel.biometricManager.authenticate()

        switch result {
        case .success:
            // Transition to authenticated after a brief delay (1 second)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            viewModel.authState = .authenticated

        case .cancelled:
            // Show retry and fallback buttons without error message
            showRetryButton = true
            showError = false

        case .failed(let message):
            // Show error + retry/fallback buttons
            showRetryButton = true
            showError = true
            errorMessage = message

        case .tokenExpired:
            // Token expired — go directly to login
            viewModel.authState = .login

        case .networkError:
            // Show error + retry/fallback buttons
            showRetryButton = true
            showError = true
            errorMessage = "Errore di connessione. Verifica la rete."

            // After 3 retries with network error: auto-transition to .login
            if retryCount >= maxRetries {
                viewModel.authState = .login
            }
        }
    }
}
