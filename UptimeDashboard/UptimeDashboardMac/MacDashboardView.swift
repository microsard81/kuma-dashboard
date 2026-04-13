import SwiftUI

// MARK: - Color hex extension for macOS
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct MacDashboardView: View {
    @EnvironmentObject var viewModel: MacAppViewModel
    @Environment(\.colorScheme) var colorScheme
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

    private var dashboardBackground: Color {
        colorScheme == .dark ? Color(hex: "#141c2b") : Color(.windowBackgroundColor)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
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

            Divider()

            // Lista monitor
            ScrollView {
                LazyVStack(spacing: 0) {
                    let downItems = filteredMonitors.filter { $0.isDown }
                    let mismatchItems = filteredMonitors.filter { $0.isMismatch }
                    let upItems = filteredMonitors.filter { !$0.isDown && !$0.isMismatch }
                    let allUp = downItems.isEmpty && mismatchItems.isEmpty

                    if !downItems.isEmpty {
                        SectionHeader(title: "DOWN", icon: "xmark.circle.fill", color: .red)
                        ForEach(downItems) { monitor in
                            MacMonitorRow(monitor: monitor)
                                .background(Color.red.opacity(0.12))
                        }
                    }

                    if !mismatchItems.isEmpty {
                        SectionHeader(title: "Mismatch", icon: "exclamationmark.triangle.fill", color: .yellow)
                        ForEach(mismatchItems) { monitor in
                            MacMonitorRow(monitor: monitor)
                                .background(Color.yellow.opacity(0.10))
                        }
                    }

                    if !upItems.isEmpty {
                        if !allUp {
                            SectionHeader(title: "UP", icon: "checkmark.circle.fill", color: .green)
                        }
                        ForEach(upItems) { monitor in
                            MacMonitorRow(monitor: monitor)
                        }
                    }
                }
            }
        }
        .background(dashboardBackground)
        .preferredColorScheme(.dark)
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

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundColor(color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(color.opacity(0.05))
    }
}

// MARK: - Monitor Row

private struct MacMonitorRow: View {
    let monitor: MacMonitor
    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let urlString = monitor.link, let url = URL(string: urlString) {
                    Button { openURL(url) } label: {
                        Text(monitor.name).font(.body.weight(.semibold)).foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(monitor.name).font(.body.weight(.semibold))
                }
                Spacer()
                Text(monitor.finalStatus)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor)
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                ProbeIndicator(label: "Aruba", status: monitor.k1)
                ProbeIndicator(label: "TIM", status: monitor.k2)
                ProbeIndicator(label: "ILIAD", status: monitor.k3)
                ProbeIndicator(label: "NodePing", status: monitor.n1)
                Spacer()
            }

            // Sparkline
            MacSparklineView(history: monitor.history)
                .frame(height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)

        Divider().padding(.leading, 16)
    }

    private var badgeColor: Color {
        monitor.isDown ? .red : (monitor.isMismatch ? .yellow : .green)
    }
}

// MARK: - Probe Indicator

private struct ProbeIndicator: View {
    let label: String
    let status: String

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(status == "UP" ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Sparkline (semplificata per macOS, senza gesture)

private struct MacSparklineView: View {
    let history: [[String: Any]]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, severity in
                    Rectangle()
                        .fill(colorFor(severity))
                        .frame(width: barWidth(totalWidth: geo.size.width))
                }
            }
        }
    }

    private var points: [Int] {
        // history può essere [Int] o [[String:Any]] — estraiamo severity
        history.compactMap { dict in
            if let s = dict["s"] as? Int { return s }
            return nil
        }
    }

    private func colorFor(_ severity: Int) -> Color {
        switch severity {
        case 0: return Color(hex: "#34d399")
        case 1: return Color(hex: "#FFEE00")
        case 2: return Color(hex: "#f87171")
        default: return .gray
        }
    }

    private func barWidth(totalWidth: CGFloat) -> CGFloat {
        let count = max(points.count, 1)
        let spacing = CGFloat(count - 1) * 1.0
        return max(1, (totalWidth - spacing) / CGFloat(count))
    }
}
