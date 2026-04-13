import SwiftUI

struct MacLoginView: View {
    @EnvironmentObject var viewModel: MacAppViewModel

    @State private var username = ""
    @State private var password = ""
    @State private var rememberMe = false

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

                Toggle("Ricordami", isOn: $rememberMe)
                    .frame(maxWidth: 300)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }

            Button {
                Task {
                    await viewModel.login(username: username, password: password, rememberMe: rememberMe)
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

            Spacer()
        }
        .padding()
    }
}
