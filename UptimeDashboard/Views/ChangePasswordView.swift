import SwiftUI

struct ChangePasswordView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""

    private var isFormValid: Bool {
        newPassword.count >= 8 && newPassword == confirmPassword
    }

    private var mismatchError: String? {
        guard !confirmPassword.isEmpty else { return nil }
        return newPassword != confirmPassword ? "Le password non corrispondono" : nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#141c2b")
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "lock.rotation")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text("Cambio password obbligatorio")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)

                    Text("Per motivi di sicurezza, devi impostare una nuova password.\nRequisiti: almeno 8 caratteri, una maiuscola, una minuscola, un numero e un carattere speciale.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(spacing: 16) {
                        SecureField("Nuova password (min. 8 caratteri)", text: $newPassword)
                            .textContentType(.newPassword)
                            .padding()
                            .foregroundColor(.primary)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)

                        SecureField("Conferma password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .padding()
                            .foregroundColor(.primary)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    if let error = mismatchError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }

                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }

                    Button {
                        Task { await authViewModel.changePassword(newPassword: newPassword) }
                    } label: {
                        Group {
                            if authViewModel.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Cambia password").fontWeight(.semibold)
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

                    Spacer()
                }
                .foregroundStyle(.white)
            }
            .navigationBarHidden(true)
        }
    }
}
