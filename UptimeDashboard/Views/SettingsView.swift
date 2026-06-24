import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject var settingsVM: SettingsViewModel

    // Chart limit states (needed for live SwiftUI updates)
    @State private var tempMin = ChartLimitsSettings.shared.yMin(for: "°C")
    @State private var tempMax = ChartLimitsSettings.shared.yMax(for: "°C")
    @State private var voltMin = ChartLimitsSettings.shared.yMin(for: "V")
    @State private var voltMax = ChartLimitsSettings.shared.yMax(for: "V")
    @State private var percMax = ChartLimitsSettings.shared.yMax(for: "%")
    @State private var minMin = ChartLimitsSettings.shared.yMin(for: "min")
    @State private var minMax = ChartLimitsSettings.shared.yMax(for: "min")
    @State private var kwMin = ChartLimitsSettings.shared.yMin(for: "kW")
    @State private var kwMax = ChartLimitsSettings.shared.yMax(for: "kW")

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

            // MARK: - Sezione Limiti Grafici
            Section("Temperatura (°C)") {
                chartSlider(label: "Min", value: $tempMin, range: 0...72, step: 1, color: .orange, onChanged: { ChartLimitsSettings.shared.setYMin($0, for: "°C") })
                chartSlider(label: "Max", value: $tempMax, range: 0...72, step: 1, color: .orange, onChanged: { ChartLimitsSettings.shared.setYMax($0, for: "°C") })
            }
            Section("Tensione (V)") {
                chartSlider(label: "Min", value: $voltMin, range: 0...300, step: 5, color: .yellow, onChanged: { ChartLimitsSettings.shared.setYMin($0, for: "V") })
                chartSlider(label: "Max", value: $voltMax, range: 0...300, step: 5, color: .yellow, onChanged: { ChartLimitsSettings.shared.setYMax($0, for: "V") })
            }
            Section("Capacità (%)") {
                chartSlider(label: "Max", value: $percMax, range: 0...100, step: 5, color: .blue, onChanged: { ChartLimitsSettings.shared.setYMax($0, for: "%") })
            }
            Section("Durata (min)") {
                chartSlider(label: "Min", value: $minMin, range: 0...336, step: 5, color: .purple, onChanged: { ChartLimitsSettings.shared.setYMin($0, for: "min") })
                chartSlider(label: "Max", value: $minMax, range: 0...336, step: 5, color: .purple, onChanged: { ChartLimitsSettings.shared.setYMax($0, for: "min") })
            }
            Section("Potenza (kW)") {
                chartSlider(label: "Min", value: $kwMin, range: 0...120, step: 5, color: .blue, onChanged: { ChartLimitsSettings.shared.setYMin($0, for: "kW") })
                chartSlider(label: "Max", value: $kwMax, range: 0...120, step: 5, color: .blue, onChanged: { ChartLimitsSettings.shared.setYMax($0, for: "kW") })
            }
            Section {
                Button("Ripristina predefiniti") {
                    ChartLimitsSettings.shared.resetAll()
                    tempMin = ChartLimitsSettings.shared.yMin(for: "°C")
                    tempMax = ChartLimitsSettings.shared.yMax(for: "°C")
                    voltMin = ChartLimitsSettings.shared.yMin(for: "V")
                    voltMax = ChartLimitsSettings.shared.yMax(for: "V")
                    percMax = ChartLimitsSettings.shared.yMax(for: "%")
                    minMin = ChartLimitsSettings.shared.yMin(for: "min")
                    minMax = ChartLimitsSettings.shared.yMax(for: "min")
                    kwMin = ChartLimitsSettings.shared.yMin(for: "kW")
                    kwMax = ChartLimitsSettings.shared.yMax(for: "kW")
                }
                .foregroundColor(.secondary)
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

    @ViewBuilder
    private func chartSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, color: Color, onChanged: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .tint(color)
                .onChange(of: value.wrappedValue) { newVal in
                    onChanged(newVal)
                }
            Text("\(Int(value.wrappedValue))")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}


