import SwiftUI

struct MacSettingsView: View {
    @EnvironmentObject var viewModel: MacAppViewModel

    var body: some View {
        Form {
            // Tema
            Picker("Tema", selection: $viewModel.themeMode) {
                Text("Auto").tag("auto")
                Text("Chiaro").tag("light")
                Text("Scuro").tag("dark")
            }
            .pickerStyle(.segmented)

            // Dimensione testo
            VStack(alignment: .leading) {
                HStack {
                    Text("Dimensione testo")
                    Spacer()
                    Text(textScaleLabel)
                        .foregroundColor(.secondary)
                }
                Slider(value: $viewModel.textScale, in: 0.8...1.6, step: 0.1)
                HStack {
                    Text("A").font(.caption)
                    Spacer()
                    Text("A").font(.title3)
                }
                .foregroundColor(.secondary)
            }

            // Reset
            Button("Ripristina valori predefiniti") {
                viewModel.themeMode = "dark"
                viewModel.textScale = 1.0
            }
            .foregroundColor(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 200)
        .padding()
    }

    private var textScaleLabel: String {
        let pct = Int(viewModel.textScale * 100)
        return "\(pct)%"
    }
}
