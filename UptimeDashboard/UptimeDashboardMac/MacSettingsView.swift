import SwiftUI

struct MacSettingsView: View {
    @EnvironmentObject var viewModel: MacAppViewModel

    var body: some View {
        Form {
            Picker("Tema", selection: Binding(
                get: { viewModel.themeMode },
                set: { viewModel.setTheme($0) }
            )) {
                Text("Auto").tag("auto")
                Text("Chiaro").tag("light")
                Text("Scuro").tag("dark")
            }
            .pickerStyle(.segmented)

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

            Button("Ripristina valori predefiniti") {
                viewModel.setTheme("dark")
                viewModel.setTextScale(1.0)
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
