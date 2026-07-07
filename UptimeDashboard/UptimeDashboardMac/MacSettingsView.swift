import SwiftUI
import UniformTypeIdentifiers

struct MacSettingsView: View {
    @EnvironmentObject var viewModel: MacAppViewModel

    // Chart limit states
    @State private var tempMin = ChartLimitsSettings.shared.yMin(for: "°C")
    @State private var tempMax = ChartLimitsSettings.shared.yMax(for: "°C")
    @State private var voltMin = ChartLimitsSettings.shared.yMin(for: "V")
    @State private var voltMax = ChartLimitsSettings.shared.yMax(for: "V")
    @State private var percMax = ChartLimitsSettings.shared.yMax(for: "%")
    @State private var minMin = ChartLimitsSettings.shared.yMin(for: "min")
    @State private var minMax = ChartLimitsSettings.shared.yMax(for: "min")
    @State private var kwMin = ChartLimitsSettings.shared.yMin(for: "kW")
    @State private var kwMax = ChartLimitsSettings.shared.yMax(for: "kW")

    // Local event log
    @State private var localLogEnabled = UserDefaults.standard.bool(forKey: "mac_local_event_log_enabled")
    @State private var localLogPath = UserDefaults.standard.string(forKey: "mac_local_event_log_path") ?? ""

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

            // Salvataggio eventi in locale
            Section("Registro eventi locale") {
                Toggle("Salva eventi in locale", isOn: $localLogEnabled)
                    .onChange(of: localLogEnabled) { newValue in
                        if newValue {
                            chooseLogFilePath()
                        } else {
                            // OFF: cancella il percorso salvato (non il file)
                            localLogPath = ""
                            UserDefaults.standard.removeObject(forKey: "mac_local_event_log_path")
                            UserDefaults.standard.removeObject(forKey: "mac_local_event_log_bookmark")
                            UserDefaults.standard.set(false, forKey: "mac_local_event_log_enabled")
                        }
                    }

                if localLogEnabled {
                    Text(localLogPath.isEmpty ? "Nessun percorso configurato" : localLogPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
        }
        .formStyle(.grouped)
        .frame(minWidth: 450, minHeight: 500)
        .padding()
    }

    private func chooseLogFilePath() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        panel.nameFieldStringValue = "\(fmt.string(from: Date()))_inva_eventi.log"
        panel.canCreateDirectories = true
        panel.message = "Scegli dove salvare il registro eventi. Se selezioni un file esistente, i nuovi eventi verranno aggiunti in fondo."
        panel.begin { result in
            if result == .OK, let url = panel.url {
                localLogPath = url.path
                UserDefaults.standard.set(url.path, forKey: "mac_local_event_log_path")
                UserDefaults.standard.set(true, forKey: "mac_local_event_log_enabled")
                if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(bookmark, forKey: "mac_local_event_log_bookmark")
                }
                // Crea il file subito se non esiste
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                // Backfill immediato con gli eventi dal server
                LocalEventLogger.shared.backfillIfNeeded()
            } else {
                if localLogPath.isEmpty {
                    localLogEnabled = false
                    UserDefaults.standard.set(false, forKey: "mac_local_event_log_enabled")
                }
            }
        }
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
