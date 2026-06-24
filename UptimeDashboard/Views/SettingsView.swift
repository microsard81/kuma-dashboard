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

            // MARK: - Sezione Limiti Grafici
            Section("Limiti Grafici") {
                ForEach(ChartLimitsSettings.configurableUnits, id: \.unit) { item in
                    let sliderMax = chartSliderMax(for: item.unit)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.label)
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(ChartLimitsSettings.shared.yMin(for: item.unit)))–\(Int(ChartLimitsSettings.shared.yMax(for: item.unit)))")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }

                        if item.unit == "%" {
                            Slider(
                                value: Binding(
                                    get: { ChartLimitsSettings.shared.yMax(for: "%") },
                                    set: { ChartLimitsSettings.shared.setYMax($0, for: "%") }
                                ),
                                in: 10...100,
                                step: 5
                            )
                        } else {
                            RangeSliderView(
                                lowerValue: Binding(
                                    get: { ChartLimitsSettings.shared.yMin(for: item.unit) },
                                    set: { ChartLimitsSettings.shared.setYMin($0, for: item.unit) }
                                ),
                                upperValue: Binding(
                                    get: { ChartLimitsSettings.shared.yMax(for: item.unit) },
                                    set: { ChartLimitsSettings.shared.setYMax($0, for: item.unit) }
                                ),
                                bounds: 0...sliderMax,
                                step: chartSliderStep(for: item.unit),
                                accentColor: chartSliderColor(for: item.unit)
                            )
                        }
                    }
                }

                Button("Ripristina predefiniti") {
                    ChartLimitsSettings.shared.resetAll()
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

    private func chartSliderMax(for unit: String) -> Double {
        switch unit {
        case "°C": return 72
        case "V": return 300
        case "min": return 336
        case "kW": return 120
        default: return 100
        }
    }

    private func chartSliderStep(for unit: String) -> Double {
        switch unit {
        case "°C": return 1
        case "V": return 5
        case "min": return 5
        case "kW": return 5
        default: return 1
        }
    }

    private func chartSliderColor(for unit: String) -> Color {
        switch unit {
        case "°C": return .orange
        case "V": return .yellow
        case "min": return .purple
        case "kW": return .blue
        default: return .accentColor
        }
    }
}


// MARK: - Range Slider

struct RangeSliderView: View {
    @Binding var lowerValue: Double
    @Binding var upperValue: Double
    let bounds: ClosedRange<Double>
    var step: Double = 1
    var accentColor: Color = .accentColor

    private let thumbSize: CGFloat = 22
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - thumbSize
            let range = bounds.upperBound - bounds.lowerBound

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(Color.gray.opacity(0.25))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbSize / 2)

                // Active range track
                let lowerX = width * (lowerValue - bounds.lowerBound) / range
                let upperX = width * (upperValue - bounds.lowerBound) / range
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(accentColor)
                    .frame(width: max(0, upperX - lowerX), height: trackHeight)
                    .offset(x: lowerX + thumbSize / 2)

                // Lower thumb
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: lowerX)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let raw = bounds.lowerBound + (value.location.x / width) * range
                                let stepped = round(raw / step) * step
                                let clamped = min(max(stepped, bounds.lowerBound), upperValue - step)
                                lowerValue = clamped
                            }
                    )

                // Upper thumb
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: upperX)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let raw = bounds.lowerBound + (value.location.x / width) * range
                                let stepped = round(raw / step) * step
                                let clamped = max(min(stepped, bounds.upperBound), lowerValue + step)
                                upperValue = clamped
                            }
                    )
            }
            .frame(height: thumbSize)
        }
        .frame(height: thumbSize)
    }
}
