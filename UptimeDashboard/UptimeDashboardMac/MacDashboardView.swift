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
        var sorted: [MacMonitor]
        switch viewModel.sortOrder {
        case "alphabetical":
            sorted = viewModel.monitors.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "globalState":
            sorted = viewModel.monitors.sorted { globalRank($0) > globalRank($1) }
        default: // severity
            sorted = viewModel.monitors.sorted { rank($0) > rank($1) }
        }
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
        .onChange(of: problemCount) { newCount in
            if newCount == 0 {
                showOnlyProblems = false
            }
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

    private func globalRank(_ m: MacMonitor) -> Int {
        // red > yellow > green
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
    @Environment(\.textScale) var scale

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.scaled(.caption, scale: scale, weight: .bold))
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
    @Environment(\.textScale) var scale
    @State private var selectionLabel: String? = nil
    @State private var hoveredSegment: MacSparklineSegment? = nil

    /// Override sonda durante hover su mismatch
    private func probeOverride(k1: Int?, k2: Int?, k3: Int?, n1: Int?, probe: String) -> String? {
        guard let seg = hoveredSegment, seg.severity == 1 else { return nil }
        let val: Int?
        switch probe {
        case "k1": val = seg.k1
        case "k2": val = seg.k2
        case "k3": val = seg.k3
        case "n1": val = seg.n1
        case "u1": val = seg.u1
        default: val = nil
        }
        guard let v = val else { return nil }
        return v == 0 ? "DOWN" : "UP"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let urlString = monitor.link, let url = URL(string: urlString) {
                    Button { openURL(url) } label: {
                        Text(monitor.name).font(.scaled(.body, scale: scale, weight: .semibold)).foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(monitor.name).font(.scaled(.body, scale: scale, weight: .semibold))
                }
                Spacer()
                Text(monitor.finalStatus)
                    .font(.scaled(.caption, scale: scale, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor)
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                ProbeIndicator(label: "Aruba", status: probeOverride(k1: nil, k2: nil, k3: nil, n1: nil, probe: "k1") ?? monitor.k1)
                ProbeIndicator(label: "TIM", status: probeOverride(k1: nil, k2: nil, k3: nil, n1: nil, probe: "k2") ?? monitor.k2)
                ProbeIndicator(label: "ILIAD", status: probeOverride(k1: nil, k2: nil, k3: nil, n1: nil, probe: "k3") ?? monitor.k3)
                ProbeIndicator(label: "NodePing", status: probeOverride(k1: nil, k2: nil, k3: nil, n1: nil, probe: "n1") ?? monitor.n1)
                ProbeIndicator(label: "Uptime", status: probeOverride(k1: nil, k2: nil, k3: nil, n1: nil, probe: "u1") ?? monitor.u1)
                Spacer()
                if let label = selectionLabel {
                    Text(label)
                        .font(.scaled(.caption2, scale: scale, weight: .bold))
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: selectionLabel)

            MacSparklineView(history: monitor.history, selectionLabel: $selectionLabel, hoveredSegment: $hoveredSegment)
                .frame(height: 28)
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
    @Environment(\.textScale) var scale

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(status == "UP" ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.scaled(.caption, scale: scale))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Sparkline con effetto fisheye e tooltip (macOS)

private struct MacSparklineView: View {
    let history: [[String: Any]]
    @Binding var selectionLabel: String?
    @Binding var hoveredSegment: MacSparklineSegment?

    private let samplingInterval: TimeInterval = 60

    @State private var hoverX: CGFloat? = nil

    private var segments: [MacSparklineSegment] {
        let pts = points
        let now = Date()
        return pts.enumerated().map { offset, point in
            let secsAgo = TimeInterval(pts.count - 1 - offset) * samplingInterval
            let timestamp = now.addingTimeInterval(-secsAgo)
            return MacSparklineSegment(id: offset, severity: point.severity,
                                        k1: point.k1, k2: point.k2, k3: point.k3, n1: point.n1, u1: point.u1,
                                        timestamp: timestamp)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let count = segments.count
            let bw = barWidth(totalWidth: geo.size.width, count: count)
            let cellWidth = bw + 1.0

            HStack(alignment: .bottom, spacing: 1) {
                ForEach(segments) { seg in
                    Rectangle()
                        .fill(colorFor(seg.severity))
                        .frame(width: bw)
                }
            }
            .frame(maxHeight: .infinity)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverX = location.x
                    let idx = Int(location.x / cellWidth)
                    if idx >= 0, idx < count {
                        let seg = segments[idx]
                        hoveredSegment = seg
                        let formatter = DateFormatter()
                        formatter.locale = Locale(identifier: "it-IT")
                        formatter.dateFormat = "HH:mm"
                        let time = formatter.string(from: seg.timestamp)
                        let status: String
                        switch seg.severity {
                        case 0: status = "UP"
                        case 1: status = "Mismatch"
                        case 2: status = "DOWN"
                        default: status = "?"
                        }
                        selectionLabel = "\(time) · \(status)"
                    }
                case .ended:
                    hoverX = nil
                    selectionLabel = nil
                    hoveredSegment = nil
                }
            }
        }
    }

    private struct HistoryPoint {
        let severity: Int
        let k1: Int?
        let k2: Int?
        let k3: Int?
        let n1: Int?
        let u1: Int?
    }

    private var points: [HistoryPoint] {
        history.compactMap { dict in
            if let s = dict["s"] as? Int {
                return HistoryPoint(severity: s,
                                    k1: dict["k1"] as? Int,
                                    k2: dict["k2"] as? Int,
                                    k3: dict["k3"] as? Int,
                                    n1: dict["n1"] as? Int,
                                    u1: dict["u1"] as? Int)
            }
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

    private func barWidth(totalWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let spacing = CGFloat(count - 1) * 1.0
        return max(1, (totalWidth - spacing) / CGFloat(count))
    }
}

private struct MacSparklineSegment: Identifiable {
    let id: Int
    let severity: Int
    let k1: Int?
    let k2: Int?
    let k3: Int?
    let n1: Int?
    let u1: Int?
    let timestamp: Date
}
