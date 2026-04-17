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
            }
            .foregroundColor(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 420)
        .padding()
    }

    private var textScaleLabel: String {
        "\(Int(viewModel.textScale * 100))%"
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
}
