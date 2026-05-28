import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel

    // MARK: - Biometric helpers

    private var deviceSupportsBiometrics: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private var biometricLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .faceID ? "Face ID" : "Touch ID"
    }

    var body: some View {
        Form {
            // MARK: - Sezione Tema
            Section("Tema") {
                Picker("Modalità", selection: $settingsVM.themeMode) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: settingsVM.themeMode) { newValue in
                    settingsVM.setTheme(newValue)
                }
            }

            // MARK: - Sezione Ordinamento
            Section("Ordinamento") {
                Picker("Criterio", selection: $settingsVM.sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .onChange(of: settingsVM.sortOrder) { newValue in
                    settingsVM.setSortOrder(newValue)
                }
            }

            // MARK: - Sezione Auto-refresh
            Section("Auto-refresh") {
                Picker("Intervallo", selection: $settingsVM.refreshInterval) {
                    ForEach(RefreshInterval.allCases, id: \.self) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .onChange(of: settingsVM.refreshInterval) { newValue in
                    settingsVM.setRefreshInterval(newValue)
                }
            }

            // MARK: - Sezione Notifiche
            Section("Notifiche") {
                if settingsVM.notificationPermissionDenied {
                    Toggle("Notifiche push", isOn: .constant(false))
                        .disabled(true)
                    Text("Le notifiche sono disabilitate nelle Impostazioni di iOS. Abilitale da Impostazioni > Notifiche.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Toggle("Notifiche push", isOn: Binding(
                        get: { settingsVM.notificationsEnabled },
                        set: { _ in
                            Task { await settingsVM.toggleNotifications() }
                        }
                    ))
                }

                if settingsVM.notificationsEnabled {
                    Picker("Soglia notifica", selection: $settingsVM.notificationThreshold) {
                        ForEach(1...5, id: \.self) { value in
                            Text(thresholdLabel(value)).tag(value)
                        }
                    }
                    .onChange(of: settingsVM.notificationThreshold) { newValue in
                        settingsVM.setNotificationThreshold(newValue)
                    }
                }
            }

            // MARK: - Sezione Esperienza
            Section("Esperienza") {
                Toggle("Feedback aptico", isOn: $settingsVM.hapticEnabled)
                    .onChange(of: settingsVM.hapticEnabled) { newValue in
                        settingsVM.setHapticEnabled(newValue)
                    }

                Toggle("Mostra badge stato risorse", isOn: $settingsVM.badgeEnabled)
                    .onChange(of: settingsVM.badgeEnabled) { newValue in
                        settingsVM.setBadgeEnabled(newValue)
                    }
            }

            // MARK: - Sezione Sicurezza
            Section("Sicurezza") {
                if deviceSupportsBiometrics {
                    Toggle(biometricLabel, isOn: $settingsVM.biometricEnabled)
                        .onChange(of: settingsVM.biometricEnabled) { newValue in
                            settingsVM.setBiometricEnabled(newValue)
                        }
                } else {
                    Toggle(biometricLabel, isOn: .constant(false))
                        .disabled(true)
                    Text("La biometria non è disponibile su questo dispositivo.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // MARK: - Sezione Info App
            Section("Info App") {
                HStack {
                    Text("Versione")
                    Spacer()
                    Text(settingsVM.appVersion)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Connessione")
                    Spacer()
                    switch settingsVM.connectionStatus {
                    case .checking:
                        ProgressView()
                            .controlSize(.small)
                    case .connected:
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 10, height: 10)
                            Text("Connesso")
                                .foregroundColor(.green)
                        }
                    case .disconnected:
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.red)
                                .frame(width: 10, height: 10)
                            Text("Non connesso")
                                .foregroundColor(.red)
                        }
                    }
                }
                if settingsVM.connectionStatus == .disconnected {
                    Button("Riprova") {
                        Task { await settingsVM.checkConnectionStatus() }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await settingsVM.checkNotificationPermission()
                await settingsVM.checkConnectionStatus()
            }
        }
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Threshold label helper

    private func thresholdLabel(_ value: Int) -> String {
        switch value {
        case 1: return "1 sonda DOWN"
        case 2: return "2 sonde DOWN"
        case 3: return "3 sonde DOWN"
        case 4: return "4 sonde DOWN"
        case 5: return "5 sonde DOWN (tutte)"
        default: return "\(value) sonde DOWN"
        }
    }
}
