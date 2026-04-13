import SwiftUI

struct MacDashboardView: View {
    @EnvironmentObject var viewModel: MacAppViewModel
    @State private var showOnlyProblems = false

    private var filteredMonitors: [MacMonitor] {
        let sorted = viewModel.monitors.sorted { rank($0) > rank($1) }
        if showOnlyProblems {
            return sorted.filter { $0.isDown || $0.isMismatch }
        }
        return sorted
    }

    private var problemCount: Int {
        viewModel.monitors.filter { $0.isDown || $0.isMismatch }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // LED globale
                Circle()
                    .fill(ledColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: ledColor.opacity(0.6), radius: 4)

                if problemCount > 0 {
                    Text("\(problemCount)")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }

                Text("INVA Dashboard")
                    .font(.headline)

                Spacer()

                if let date = viewModel.lastUpdated {
                    Text("Aggiornato: \(date, style: .time)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if problemCount > 0 {
                    Toggle(isOn: $showOnlyProblems) {
                        Label("Solo problemi", systemImage: showOnlyProblems
                              ? "exclamationmark.triangle.fill"
                              : "exclamationmark.triangle")
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }

                Button {
                    Task { await viewModel.fetchDashboard() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .controlSize(.small)

                Button {
                    viewModel.logout()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Lista monitor
            List {
                let downItems = filteredMonitors.filter { $0.isDown }
                let mismatchItems = filteredMonitors.filter { $0.isMismatch }
                let upItems = filteredMonitors.filter { !$0.isDown && !$0.isMismatch }
                let allUp = downItems.isEmpty && mismatchItems.isEmpty

                if !downItems.isEmpty {
                    Section {
                        ForEach(downItems) { MacMonitorRow(monitor: $0) }
                    } header: {
                        Label("DOWN", systemImage: "xmark.circle.fill").foregroundColor(.red)
                    }
                }

                if !mismatchItems.isEmpty {
                    Section {
                        ForEach(mismatchItems) { MacMonitorRow(monitor: $0) }
                    } header: {
                        Label("Mismatch", systemImage: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                    }
                }

                if !upItems.isEmpty {
                    if allUp {
                        ForEach(upItems) { MacMonitorRow(monitor: $0) }
                    } else {
                        Section {
                            ForEach(upItems) { MacMonitorRow(monitor: $0) }
                        } header: {
                            Label("UP", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var ledColor: Color {
        switch viewModel.globalState {
        case "RED": return .red
        case "YELLOW": return .yellow
        default: return .green
        }
    }

    private func rank(_ m: MacMonitor) -> Int {
        if m.isDown { return 2 }
        if m.isMismatch { return 1 }
        return 0
    }
}

// MARK: - Monitor Row

private struct MacMonitorRow: View {
    let monitor: MacMonitor
    @Environment(\.openURL) var openURL

    var body: some View {
        HStack(spacing: 12) {
            // Nome (cliccabile se ha link)
            if let urlString = monitor.link, let url = URL(string: urlString) {
                Button { openURL(url) } label: {
                    Text(monitor.name).foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Text(monitor.name)
            }

            Spacer()

            // Sonde
            HStack(spacing: 8) {
                ProbeLabel(name: "Aruba", status: monitor.k1)
                ProbeLabel(name: "TIM", status: monitor.k2)
                ProbeLabel(name: "ILIAD", status: monitor.k3)
                ProbeLabel(name: "NodePing", status: monitor.n1)
            }

            // Badge stato
            Text(monitor.finalStatus)
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(badgeColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }

    private var badgeColor: Color {
        monitor.isDown ? .red : (monitor.isMismatch ? .yellow : .green)
    }
}

// MARK: - Probe Label

private struct ProbeLabel: View {
    let name: String
    let status: String

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(status == "UP" ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
