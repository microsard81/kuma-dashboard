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
    @Environment(\.textScale) var scale
    @State private var showOnlyProblems = false
    @State private var showNotificationHistory = false
    @State private var sectionOrder: [String] = UserDefaults.standard.stringArray(forKey: "mac_dashboard_section_order") ?? ["portali", "temperatura", "potenza"]
    @State private var isPortalsCollapsed = false
    @State private var isTemperatureCollapsed = false
    @State private var isPowerCollapsed = false
    @State private var allCollapsed = false

    private let sectionOrderKey = "mac_dashboard_section_order"

    private var displayOrder: [String] {
        sectionOrder
    }

    private var filteredMonitors: [MacMonitor] {
        var sorted: [MacMonitor]
        switch viewModel.sortOrder {
        case "alphabetical":
            sorted = viewModel.monitors.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "globalState":
            sorted = viewModel.monitors.sorted { globalRank($0) > globalRank($1) }
        default:
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

    // MARK: - Sensor status colors

    private var temperatureStatusColor: Color {
        guard let t = viewModel.sensorThresholds else { return .orange }
        let sensors = viewModel.sensors.filter { $0.category == .temperature }
        if sensors.contains(where: { $0.alertStatus(thresholds: t) == .critical }) { return .red }
        if sensors.contains(where: { $0.alertStatus(thresholds: t) == .warning }) { return .yellow }
        return .orange
    }

    private var powerStatusColor: Color {
        guard let t = viewModel.sensorThresholds else { return .blue }
        let sensors = viewModel.sensors.filter { $0.category == .power }
        if sensors.contains(where: { $0.alertStatus(thresholds: t) == .critical }) { return .red }
        if sensors.contains(where: { $0.alertStatus(thresholds: t) == .warning }) { return .yellow }
        return .blue
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Dashboard INVA")
                    .font(.scaled(.headline, scale: scale))

                Spacer()

                if let date = viewModel.lastUpdated {
                    Text("Aggiornato: \(date, style: .time)")
                        .font(.scaled(.caption, scale: scale))
                        .foregroundColor(.secondary)
                }

                // Section order menu (first)
                Menu {
                    Button("Portali · Temperatura · Potenza") {
                        UserDefaults.standard.set(["portali", "temperatura", "potenza"], forKey: sectionOrderKey)
                        sectionOrder = ["portali", "temperatura", "potenza"]
                    }
                    Button("Portali · Potenza · Temperatura") {
                        UserDefaults.standard.set(["portali", "potenza", "temperatura"], forKey: sectionOrderKey)
                        sectionOrder = ["portali", "potenza", "temperatura"]
                    }
                    Button("Temperatura · Potenza · Portali") {
                        UserDefaults.standard.set(["temperatura", "potenza", "portali"], forKey: sectionOrderKey)
                        sectionOrder = ["temperatura", "potenza", "portali"]
                    }
                    Button("Temperatura · Portali · Potenza") {
                        UserDefaults.standard.set(["temperatura", "portali", "potenza"], forKey: sectionOrderKey)
                        sectionOrder = ["temperatura", "portali", "potenza"]
                    }
                    Button("Potenza · Temperatura · Portali") {
                        UserDefaults.standard.set(["potenza", "temperatura", "portali"], forKey: sectionOrderKey)
                        sectionOrder = ["potenza", "temperatura", "portali"]
                    }
                    Button("Potenza · Portali · Temperatura") {
                        UserDefaults.standard.set(["potenza", "portali", "temperatura"], forKey: sectionOrderKey)
                        sectionOrder = ["potenza", "portali", "temperatura"]
                    }
                } label: {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Riordina sezioni")

                // Collapse/Expand all
                Button {
                    withAnimation {
                        allCollapsed.toggle()
                        isPortalsCollapsed = allCollapsed
                        isTemperatureCollapsed = allCollapsed
                        isPowerCollapsed = allCollapsed
                    }
                } label: {
                    Image(systemName: allCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help(allCollapsed ? "Espandi tutto" : "Comprimi tutto")

                // Refresh
                Button {
                    Task { await viewModel.fetchDashboard() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Aggiorna")

                // Notifications
                Button {
                    showNotificationHistory = true
                } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showNotificationHistory) {
                    MacNotificationHistoryPopover()
                        .frame(width: 350, height: 400)
                }
                .help("Notifiche")

                // Logout
                Button {
                    viewModel.logout()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Logout")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Main content: 3 sections responsive
            GeometryReader { geo in
                let isWide = geo.size.width > 900

                if isWide {
                    // Side by side
                    HStack(alignment: .top, spacing: 1) {
                        ForEach(displayOrder, id: \.self) { section in
                            if section != displayOrder.first {
                                Divider()
                            }
                            sectionView(for: section)
                                .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    // Stacked
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(displayOrder, id: \.self) { section in
                                if section != displayOrder.first {
                                    Divider().padding(.vertical, 4)
                                }
                                sectionView(for: section)
                            }
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

    // MARK: - Section Router

    @ViewBuilder
    private func sectionView(for section: String) -> some View {
        switch section {
        case "portali": portalsSection
        case "temperatura": temperatureSection
        case "potenza": powerSection
        default: EmptyView()
        }
    }

    // MARK: - Portals Section

    private var portalsSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(ledColor)
                Text("Portali")
                    .font(.scaled(.headline, scale: scale))
                Image(systemName: isPortalsCollapsed ? "chevron.right" : "chevron.down")
                    .font(.scaled(.caption, scale: scale))
                    .foregroundColor(.secondary)
                Spacer()
                Circle()
                    .fill(ledColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: ledColor.opacity(0.6), radius: 3)
                if problemCount > 0 {
                    Toggle(isOn: $showOnlyProblems) {
                        Label("Solo problemi", systemImage: showOnlyProblems
                              ? "exclamationmark.triangle.fill"
                              : "exclamationmark.triangle")
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(ledColor.opacity(0.05))
            .onTapGesture { withAnimation { isPortalsCollapsed.toggle() } }

            // Monitor list
            if !isPortalsCollapsed {
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
            } // end if !isPortalsCollapsed
        }
    }

    // MARK: - Temperature Section

    private var temperatureSection: some View {
        let sensors = viewModel.sensors.filter { $0.category == .temperature }
        return VStack(spacing: 0) {
            HStack {
                Image(systemName: "thermometer.medium")
                    .foregroundColor(temperatureStatusColor)
                Text("Temperatura (°C)")
                    .font(.scaled(.headline, scale: scale))
                Image(systemName: isTemperatureCollapsed ? "chevron.right" : "chevron.down")
                    .font(.scaled(.caption, scale: scale))
                    .foregroundColor(.secondary)
                Spacer()
                Circle()
                    .fill(temperatureStatusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: temperatureStatusColor.opacity(0.6), radius: 3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(temperatureStatusColor.opacity(0.05))
            .onTapGesture { withAnimation { isTemperatureCollapsed.toggle() } }

            if !isTemperatureCollapsed {

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sensors) { sensor in
                        SensorCardView(
                            sensor: sensor,
                            thresholds: viewModel.sensorThresholds,
                            historyPoints: viewModel.sensorHistory[sensor.id] ?? []
                        )
                        .padding(.horizontal, 16)
                        Divider().padding(.leading, 16)
                    }
                }
            }
            } // end if !isTemperatureCollapsed
        }
    }

    // MARK: - Power Section

    private var powerSection: some View {
        let sensors = viewModel.sensors.filter { $0.category == .power }
        return VStack(spacing: 0) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(powerStatusColor)
                Text("Potenza (kW)")
                    .font(.scaled(.headline, scale: scale))
                Image(systemName: isPowerCollapsed ? "chevron.right" : "chevron.down")
                    .font(.scaled(.caption, scale: scale))
                    .foregroundColor(.secondary)
                Spacer()
                Circle()
                    .fill(powerStatusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: powerStatusColor.opacity(0.6), radius: 3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(powerStatusColor.opacity(0.05))
            .onTapGesture { withAnimation { isPowerCollapsed.toggle() } }

            if !isPowerCollapsed {

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sensors) { sensor in
                        SensorCardView(
                            sensor: sensor,
                            thresholds: viewModel.sensorThresholds,
                            historyPoints: viewModel.sensorHistory[sensor.id] ?? []
                        )
                        .padding(.horizontal, 16)
                        Divider().padding(.leading, 16)
                    }
                }
            }
            } // end if !isPowerCollapsed
        }
    }

    // MARK: - Helpers

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

    private func probeOverride(probe: String) -> String? {
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
                ProbeIndicator(label: "Aruba", status: probeOverride(probe: "k1") ?? monitor.k1)
                ProbeIndicator(label: "TIM", status: probeOverride(probe: "k2") ?? monitor.k2)
                ProbeIndicator(label: "ILIAD", status: probeOverride(probe: "k3") ?? monitor.k3)
                ProbeIndicator(label: "NodePing", status: probeOverride(probe: "n1") ?? monitor.n1)
                ProbeIndicator(label: "Uptime", status: probeOverride(probe: "u1") ?? monitor.u1)
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

// MARK: - Sparkline con tooltip (macOS)

private struct MacSparklineView: View {
    let history: [[String: Any]]
    @Binding var selectionLabel: String?
    @Binding var hoveredSegment: MacSparklineSegment?

    private let samplingInterval: TimeInterval = 60

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
                    let idx = Int(location.x / cellWidth)
                    if idx >= 0, idx < count {
                        let seg = segments[idx]
                        hoveredSegment = seg
                        let formatter = DateFormatter()
                        formatter.locale = Locale(identifier: "it-IT")
                        formatter.dateFormat = "HH:mm"
                        selectionLabel = formatter.string(from: seg.timestamp)
                    }
                case .ended:
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

// MARK: - Notification History Popover (macOS)

private struct MacNotificationHistoryPopover: View {
    @State private var notifications: [NotificationRecord] = []
    @Environment(\.textScale) var scale

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notifiche")
                    .font(.scaled(.headline, scale: scale))
                Spacer()
            }
            .padding()

            Divider()

            if notifications.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.slash")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("Nessuna notifica")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(notifications) { notif in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(notif.title)
                                .font(.caption.bold())
                            Spacer()
                            Text(formatDate(notif.date))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if !notif.body.isEmpty {
                            Text(notif.body)
                                .font(.scaled(.caption, scale: scale))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
        .onAppear { notifications = NotificationStore.shared.loadAll() }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Ieri' HH:mm"
        } else {
            formatter.dateFormat = "dd/MM HH:mm"
        }
        return formatter.string(from: date)
    }
}
