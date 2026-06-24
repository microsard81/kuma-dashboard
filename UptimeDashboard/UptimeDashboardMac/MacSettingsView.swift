import SwiftUI

struct MacSettingsView: View {
    @EnvironmentObject var viewModel: MacAppViewModel

    var body: some View {
        Form {
            // Tema
            Picker("Tema", selection: Binding(
                get: { viewModel.themeMode },
                set: { viewModel.setTheme($0) }
            )) {
                Text("Auto").tag("auto")
                Text("Chiaro").tag("light")
                Text("Scuro").tag("dark")
            }
            .pickerStyle(.segmented)

            // Ordinamento
            Picker("Ordinamento", selection: Binding(
                get: { viewModel.sortOrder },
                set: { viewModel.setSortOrder($0) }
            )) {
                Text("Per gravità").tag("severity")
                Text("Alfabetico").tag("alphabetical")
                Text("Per stato globale").tag("globalState")
            }

            // Intervallo refresh
            Picker("Auto-refresh", selection: Binding(
                get: { viewModel.refreshInterval },
                set: { viewModel.setRefreshInterval($0) }
            )) {
                Text("10 secondi").tag(10)
                Text("30 secondi").tag(30)
                Text("60 secondi").tag(60)
                Text("Disabilitato").tag(0)
            }

            // Dimensione testo
            VStack(alignment: .leading) {
                HStack {
                    Text("Dimensione testo")
                    Spacer()
                    Text(textScaleLabel)
                        .foregroundColor(.secondary)
                }
                Slider(value: Binding(
                    get: { viewModel.textScale },
                    set: { viewModel.setTextScale($0) }
                ), in: 0.8...1.6, step: 0.1)
                HStack {
                    Text("A").font(.caption)
                    Spacer()
                    Text("A").font(.title3)
                }
                .foregroundColor(.secondary)
            }

            // Badge
            Toggle("Mostra badge stato risorse", isOn: Binding(
                get: { viewModel.badgeEnabled },
                set: { viewModel.setBadgeEnabled($0) }
            ))

            // Autenticazione biometrica
            if viewModel.biometricManager.checkAvailability() != .none {
                Toggle(biometricToggleLabel, isOn: Binding(
                    get: { viewModel.biometricEnabled },
                    set: { viewModel.setBiometricEnabled($0) }
                ))
            }

            // Notifiche push
            Toggle("Notifiche push", isOn: Binding(
                get: { viewModel.notificationsEnabled },
                set: { viewModel.setNotificationsEnabled($0) }
            ))

            // Soglia notifica (visibile solo se notifiche abilitate)
            if viewModel.notificationsEnabled {
                Picker("Soglia notifica", selection: Binding(
                    get: { viewModel.notificationThreshold },
                    set: { viewModel.setNotificationThreshold($0) }
                )) {
                    ForEach(1...5, id: \.self) { value in
                        Text(thresholdLabel(value)).tag(value)
                    }
                }
            }

            // Reset
            Button("Ripristina valori predefiniti") {
                viewModel.setTheme("dark")
                viewModel.setTextScale(1.0)
                viewModel.setRefreshInterval(60)
                viewModel.setSortOrder("severity")
                viewModel.setBadgeEnabled(true)
                ChartLimitsSettings.shared.resetAll()
            }
            .foregroundColor(.secondary)

            // Limiti Grafici
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
                            // Simple slider for percentage (always 0-100)
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
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 620)
        .padding()
    }

    private var textScaleLabel: String {
        "\(Int(viewModel.textScale * 100))%"
    }

    private var biometricToggleLabel: String {
        switch viewModel.biometricManager.availableMethod {
        case .touchID:
            return "Sblocco con Touch ID"
        case .appleWatch:
            return "Sblocco con Apple Watch"
        case .both:
            return "Sblocco con Touch ID / Apple Watch"
        case .none:
            return "Sblocco biometrico"
        }
    }

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
        case "°C": return 72     // 60 + 20%
        case "V": return 300     // 250 + 20%
        case "min": return 336   // 280 + 20%
        case "kW": return 120    // 100 + 20%
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
