import SwiftUI

struct MacChangePasswordView: View {
    @EnvironmentObject var viewModel: MacAppViewModel

    @State private var newPassword = ""
    @State private var confirmPassword = ""

    private var isFormValid: Bool {
        newPassword.count >= 8 && newPassword == confirmPassword
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.rotation")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Cambio password obbligatorio")
                .font(.title2.bold())

            Text("Requisiti: almeno 8 caratteri, una maiuscola, una minuscola, un numero e un carattere speciale.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 12) {
                SecureField("Nuova password", text: $newPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                SecureField("Conferma password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            }

            if !confirmPassword.isEmpty && newPassword != confirmPassword {
                Text("Le password non corrispondono")
                    .foregroundColor(.red)
                    .font(.footnote)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }

            Button {
                Task { await viewModel.changePassword(newPassword: newPassword) }
            } label: {
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Cambia password")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isFormValid || viewModel.isLoading)
            .keyboardShortcut(.defaultAction)

            Spacer()
        }
        .padding()
    }
}
