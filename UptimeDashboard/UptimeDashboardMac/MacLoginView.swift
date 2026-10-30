import SwiftUI

struct MacLoginView: View {
    @EnvironmentObject var viewModel: MacAppViewModel

    @State private var username = ""
    @State private var password = ""
    @State private var showForgotPassword = false

    private var isFormValid: Bool {
        !username.isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "chart.bar.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("INVA Dashboard")
                .font(.largeTitle.bold())

            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }

            Button {
                Task {
                    await viewModel.login(username: username, password: password)
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Accedi")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isFormValid || viewModel.isLoading)
            .keyboardShortcut(.defaultAction)

            Button("Password dimenticata?") { showForgotPassword = true }
                .buttonStyle(.link)

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showForgotPassword) {
            MacForgotPasswordSheet(initialUsername: username)
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Forgot Password Sheet

private struct MacForgotPasswordSheet: View {
    @EnvironmentObject var viewModel: MacAppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username: String
    @State private var isSending = false
    @State private var outcome: MacPasswordResetOutcome?

    init(initialUsername: String) {
        _username = State(initialValue: initialUsername)
    }

    private var isSent: Bool {
        if case .sent = outcome { return true }
        return false
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Password dimenticata")
                .font(.title2.bold())

            Text("Inserisci il tuo username: se l'account ha un'email associata riceverai un link valido 30 minuti. Dopo il reset il 2FA andrà riconfigurato e verrai disconnesso da tutti i dispositivi.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Username", text: $username)
                .textContentType(.username)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .disabled(isSending || isSent)

            if let outcome {
                switch outcome {
                case .sent(let message):
                    Label(message, systemImage: "envelope")
                        .foregroundColor(.green)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                case .failed(let message):
                    Text(message)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: 12) {
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button {
                    Task {
                        isSending = true
                        outcome = await viewModel.requestPasswordReset(username: trimmedUsername)
                        isSending = false
                    }
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Invia link")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedUsername.isEmpty || isSending || isSent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
