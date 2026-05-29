import SwiftUI
import WidgetKit

// MARK: - Widget Definition

struct UptimeDashboardWidget: Widget {
    let kind = "UptimeDashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DashboardTimelineProvider()) { entry in
            WidgetEntryView(entry: entry)
                .containerBackground(Color(hex: "#141c2b"), for: .widget)
        }
        .configurationDisplayName("INVA Dashboard")
        .description("Stato dei servizi monitorati")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry View (router per dimensione)

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: DashboardEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget: 3 macro areas compact

struct SmallWidgetView: View {
    let entry: DashboardEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("INVA")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if !entry.isPlaceholder {
                    Text(entry.date, style: .time)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }

            if entry.isPlaceholder {
                Spacer()
                Text("Caricamento...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Spacer(minLength: 2)

                // Portali
                MacroRow(icon: "globe", title: "Portali", color: portalsColor, detail: portalsDetail)
                // Temperatura
                MacroRow(icon: "thermometer.medium", title: "Temperatura", color: temperatureColor, detail: temperatureDetail)
                // Potenza
                MacroRow(icon: "bolt.fill", title: "Potenza", color: powerColor, detail: powerDetail)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var portalsColor: Color {
        if entry.downCount > 0 { return .red }
        if entry.mismatchCount > 0 { return .yellow }
        return .green
    }

    private var portalsDetail: String {
        if entry.downCount > 0 { return "\(entry.downCount) DOWN" }
        if entry.mismatchCount > 0 { return "\(entry.mismatchCount) ⚠" }
        return "OK (\(entry.monitors.count))"
    }

    private var temperatureColor: Color {
        guard let alerts = entry.sensorAlerts else { return .orange }
        if alerts.hasCritical { return .red }
        if alerts.hasAlerts { return .yellow }
        return .orange
    }

    private var temperatureDetail: String {
        if entry.sensorError { return "—" }
        guard let alerts = entry.sensorAlerts else { return "—" }
        if alerts.hasAlerts { return "\(alerts.totalCount) ⚠" }
        return "OK"
    }

    private var powerColor: Color {
        return .blue
    }

    private var powerDetail: String {
        if entry.sensorError { return "—" }
        return "OK"
    }
}

// MARK: - Medium Widget: lista monitor con sonde

struct MediumWidgetView: View {
    let entry: DashboardEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(ledColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: ledColor.opacity(0.6), radius: 4)
                Text("INVA Dashboard")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                Spacer()
                if !entry.isPlaceholder {
                    Text(entry.date, style: .time)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 2)

            if entry.isPlaceholder {
                Spacer()
                HStack { Spacer(); Text("Caricamento...").font(.caption).foregroundColor(.secondary); Spacer() }
                Spacer()
            } else {
                ForEach(sortedMonitors.prefix(5)) { monitor in
                    HStack(spacing: 6) {
                        Text(shortName(monitor.name))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ProbeDotsView(monitor: monitor)
                        Text(monitor.finalStatus)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(statusColor(monitor))
                            .frame(width: 32)
                    }
                    .padding(.vertical, 1)
                }

                if entry.monitors.count > 5 {
                    Text("+\(entry.monitors.count - 5) altri servizi")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                if !entry.sensorError {
                    if let alerts = entry.sensorAlerts, alerts.hasAlerts {
                        HStack(spacing: 4) {
                            Circle().fill(alerts.hasCritical ? Color.red : Color.yellow).frame(width: 6, height: 6)
                            Text("\(alerts.totalCount) sensori in allarme")
                                .font(.system(size: 9))
                                .foregroundColor(alerts.hasCritical ? .red : .yellow)
                        }
                        .padding(.top, 2)
                    } else if entry.sensorAlerts != nil {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("Sensori OK").font(.system(size: 9)).foregroundColor(.green)
                        }
                        .padding(.top, 2)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sortedMonitors: [WidgetMonitor] {
        entry.monitors.sorted { rank($0) > rank($1) }
    }

    private func rank(_ m: WidgetMonitor) -> Int {
        if m.isDown { return 2 }
        if m.isMismatch { return 1 }
        return 0
    }

    private func statusColor(_ m: WidgetMonitor) -> Color {
        if m.isDown { return .red }
        if m.isMismatch { return .yellow }
        return .green
    }

    private var ledColor: Color {
        switch entry.globalState {
        case "RED": return .red
        case "YELLOW": return .yellow
        default: return .green
        }
    }
}

// MARK: - Large Widget: tutti i servizi con sonde

struct LargeWidgetView: View {
    let entry: DashboardEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(ledColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: ledColor.opacity(0.6), radius: 4)
                Text("INVA Dashboard")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                Spacer()
                if !entry.isPlaceholder {
                    Text(entry.date, style: .time)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 2)

            if entry.isPlaceholder {
                Spacer()
                HStack { Spacer(); Text("Caricamento...").font(.caption).foregroundColor(.secondary); Spacer() }
                Spacer()
            } else {
                ForEach(sortedMonitors.prefix(8)) { monitor in
                    HStack(spacing: 6) {
                        Text(shortName(monitor.name))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ProbeDotsView(monitor: monitor)
                        Text(monitor.finalStatus)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(statusColor(monitor))
                            .frame(width: 32)
                    }
                    .padding(.vertical, 1)
                }

                if entry.monitors.count > 8 {
                    Text("+\(entry.monitors.count - 8) altri servizi")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                if !entry.sensorError {
                    if let alerts = entry.sensorAlerts, alerts.hasAlerts {
                        HStack(spacing: 4) {
                            Circle().fill(alerts.hasCritical ? Color.red : Color.yellow).frame(width: 6, height: 6)
                            Text("\(alerts.totalCount) sensori in allarme")
                                .font(.system(size: 9))
                                .foregroundColor(alerts.hasCritical ? .red : .yellow)
                        }
                        .padding(.top, 2)
                    } else if entry.sensorAlerts != nil {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("Sensori OK").font(.system(size: 9)).foregroundColor(.green)
                        }
                        .padding(.top, 2)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sortedMonitors: [WidgetMonitor] {
        entry.monitors.sorted { rank($0) > rank($1) }
    }

    private func rank(_ m: WidgetMonitor) -> Int {
        if m.isDown { return 2 }
        if m.isMismatch { return 1 }
        return 0
    }

    private func statusColor(_ m: WidgetMonitor) -> Color {
        if m.isDown { return .red }
        if m.isMismatch { return .yellow }
        return .green
    }

    private var ledColor: Color {
        switch entry.globalState {
        case "RED": return .red
        case "YELLOW": return .yellow
        default: return .green
        }
    }
}

// MARK: - MacroRow (compact, for small widget)

private struct MacroRow: View {
    let icon: String
    let title: String
    let color: Color
    let detail: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Text(detail)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
        }
    }
}

// MARK: - Probe Dots (5 pallini compatti)

private struct ProbeDotsView: View {
    let monitor: WidgetMonitor

    var body: some View {
        HStack(spacing: 2) {
            Circle().fill(monitor.k1 == "UP" ? Color.green : Color.red).frame(width: 5, height: 5)
            Circle().fill(monitor.k2 == "UP" ? Color.green : Color.red).frame(width: 5, height: 5)
            Circle().fill(monitor.k3 == "UP" ? Color.green : Color.red).frame(width: 5, height: 5)
            Circle().fill(monitor.n1 == "UP" ? Color.green : Color.red).frame(width: 5, height: 5)
            Circle().fill(monitor.u1 == "UP" ? Color.green : Color.red).frame(width: 5, height: 5)
        }
    }
}

// MARK: - Helper

private func shortName(_ name: String) -> String {
    name.replacingOccurrences(of: "INVA - ", with: "")
}

// MARK: - Color hex (widget target)

extension Color {
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

// MARK: - Previews

#if DEBUG
#Preview("Small", as: .systemSmall) {
    UptimeDashboardWidget()
} timeline: {
    DashboardEntry(date: Date(), globalState: "GREEN", monitors: [], downCount: 0, mismatchCount: 0, sensorAlerts: nil, sensorError: false, isPlaceholder: false)
}

#Preview("Medium", as: .systemMedium) {
    UptimeDashboardWidget()
} timeline: {
    DashboardEntry(date: Date(), globalState: "YELLOW", monitors: [
        WidgetMonitor(name: "INVA - www.regione.vda.it", k1: "UP", k2: "UP", k3: "UP", n1: "DOWN", u1: "UP", finalStatus: "UP"),
    ], downCount: 0, mismatchCount: 1, sensorAlerts: SensorAlerts(warningCount: 1, criticalCount: 0), sensorError: false, isPlaceholder: false)
}

#Preview("Large", as: .systemLarge) {
    UptimeDashboardWidget()
} timeline: {
    DashboardEntry(date: Date(), globalState: "GREEN", monitors: [
        WidgetMonitor(name: "INVA - www.regione.vda.it", k1: "UP", k2: "UP", k3: "UP", n1: "UP", u1: "UP", finalStatus: "UP"),
        WidgetMonitor(name: "INVA - mail.cst.inva.it", k1: "UP", k2: "UP", k3: "UP", n1: "UP", u1: "UP", finalStatus: "UP"),
    ], downCount: 0, mismatchCount: 0, sensorAlerts: nil, sensorError: false, isPlaceholder: false)
}
#endif
