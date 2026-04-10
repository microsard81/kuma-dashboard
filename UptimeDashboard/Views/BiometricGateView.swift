// Feature: ios-native-app

import SwiftUI
import LocalAuthentication

/// Schermata mostrata all'avvio quando c'è una sessione salvata.
/// Tenta Face ID automaticamente; se fallisce mostra il pulsante manuale.
struct BiometricGateView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showManualButton = false

    var body: some View {
        ScrollView {
        VStack(spacing: 32) {
            Spacer(minLength: 40)

            Image(systemName: biometricIcon)
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("INVA Dashboard")
                .font(.largeTitle.bold())

            Text("Autenticazione in corso...")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if showManualButton {
                Button {
                    Task { await authViewModel.authenticateWithBiometrics() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: biometricIcon)
                        Text("Accedi con \(biometricLabel)")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .padding(.horizontal)

                Button {
                    authViewModel.state = .unauthenticated
                } label: {
                    Text("Usa username e password")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 40)
        }
        } // ScrollView
        .task {
            // Tenta Face ID automaticamente all'avvio
            await authViewModel.authenticateWithBiometrics()
            // Se fallisce, mostra il pulsante manuale
            if authViewModel.state != .authenticated {
                showManualButton = true
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
