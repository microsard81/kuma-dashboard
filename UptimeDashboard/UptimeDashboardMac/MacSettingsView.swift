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
        .frame(width: 400, height: 380)
        .padding()
    }

    private var textScaleLabel: String {
        "\(Int(viewModel.textScale * 100))%"
    }
}
