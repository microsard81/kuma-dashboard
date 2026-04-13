import SwiftUI

struct MacTwoFAView: View {
    @EnvironmentObject var viewModel: MacAppViewModel
    @State private var code = ""

    private var isCodeValid: Bool {
        code.count == 6 && code.allSatisfy(\.isNumber)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Verifica in due passaggi")
                .font(.title2.bold())

            Text("Inserisci il codice a 6 cifre dalla tua app di autenticazione")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("Codice TOTP", text: $code)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .multilineTextAlignment(.center)
                .font(.title2.monospacedDigit())
                .onChange(of: code) { newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(6))
                    if filtered != newValue { code = filtered }
                }

            if let error = viewModel.errorMessage {
                Text(error).foregroundColor(.red).font(.footnote)
            }

            Button {
                Task { await viewModel.verify2FA(code: code) }
            } label: {
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Verifica")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isCodeValid || viewModel.isLoading)
            .keyboardShortcut(.defaultAction)

            Spacer()
        }
        .padding()
    }
}
