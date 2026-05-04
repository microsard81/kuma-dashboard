import SwiftUI

/// Vista del menu a tendina nella barra dei menu di macOS.
/// Mostra stato globale, risorse anomale e azioni rapide.
struct MenuBarView: View {
    @EnvironmentObject var viewModel: MacAppViewModel

    var body: some View {
        // Stato globale
        HStack {
            Circle()
                .fill(ledColor)
                .frame(width: 10, height: 10)
            Text(statusLabel)
                .font(.headline)
        }

        Divider()

        // Conteggi
        let downCount = viewModel.monitors.filter(\.isDown).count
        let mismatchCount = viewModel.monitors.filter(\.isMismatch).count
        let totalCount = viewModel.monitors.count

        if downCount > 0 || mismatchCount > 0 {
            Text("\(downCount) DOWN, \(mismatchCount) mismatch su \(totalCount) risorse")
                .font(.subheadline)

            Divider()

            // Lista risorse anomale
            ForEach(viewModel.monitors.filter { $0.isDown || $0.isMismatch }) { monitor in
                HStack {
                    Image(systemName: monitor.isDown ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(monitor.isDown ? .red : .yellow)
                    Text(shortName(monitor.name))
                    Spacer()
                    Text(monitor.finalStatus)
                        .foregroundColor(monitor.isDown ? .red : .yellow)
                        .font(.caption)
                }
            }
        } else {
            Text("Tutte le \(totalCount) risorse sono UP")
                .font(.subheadline)
        }

        Divider()

        // Ultimo aggiornamento
        if let lastUpdated = viewModel.lastUpdated {
            Text("Aggiornato: \(lastUpdated, style: .time)")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        // Azioni
        Button("Aggiorna ora") {
            Task { await viewModel.fetchDashboard() }
        }
        .keyboardShortcut("r")

        Button("Apri Dashboard") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.title.contains("Dashboard") || $0.title.contains("INVA") }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
        .keyboardShortcut("d")

        Button("Impostazioni...") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        .keyboardShortcut(",")

        Divider()

        Button("Esci definitivamente") {
            // Forza la chiusura reale dell'app
            NSApp.reply(toApplicationShouldTerminate: true)
            exit(0)
        }
        .keyboardShortcut("q", modifiers: [.command, .option])
    }

    private var ledColor: Color {
        switch viewModel.globalState {
        case "RED": return .red
        case "YELLOW": return .yellow
        default: return .green
        }
    }

    private var statusLabel: String {
        switch viewModel.globalState {
        case "RED": return "Servizi DOWN"
        case "YELLOW": return "Incongruenza tra sonde"
        default: return "Tutto OK"
        }
    }

    private func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: "INVA - ", with: "")
    }
}
