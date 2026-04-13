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

// MARK: - Small Widget: LED + conteggio

struct SmallWidgetView: View {
    let entry: DashboardEntry

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(ledColor)
                .frame(width: 40, height: 40)
                .shadow(color: ledColor.opacity(0.6), radius: 8)

            Text("INVA")
                .font(.caption.bold())
                .foregroundColor(.white)

            if entry.isPlaceholder {
                Text("Caricamento...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if entry.downCount > 0 {
                Text("\(entry.downCount) DOWN")
                    .font(.caption.bold())
                    .foregroundColor(.red)
            } else if entry.mismatchCount > 0 {
                Text("\(entry.mismatchCount) Mismatch")
                    .font(.caption.bold())
                    .foregroundColor(.yellow)
            } else {
                Text("Tutto OK")
                    .font(.caption.bold())
                    .foregroundColor(.green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ledColor: Color {
        switch entry.globalState {
        case "RED": return .red
        case "YELLOW": return .yellow
        default: return .green
        }
    }
}

// MARK: - Medium Widget: LED + lista problemi

struct MediumWidgetView: View {
    let entry: DashboardEntry

    private var problemMonitors: [WidgetMonitor] {
        entry.monitors.filter { !$0.isUp }
    }

    var body: some View {
        HStack(spacing: 12) {
            // LED a sinistra
            VStack(spacing: 6) {
                Circle()
                    .fill(ledColor)
                    .frame(width: 32, height: 32)
                    .shadow(color: ledColor.opacity(0.6), radius: 6)
                Text("INVA")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
            }
            .frame(width: 60)

            // Lista problemi a destra
            VStack(alignment: .leading, spacing: 4) {
                if entry.isPlaceholder {
                    Text("Caricamento...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if problemMonitors.isEmpty {
                    Text("Tutto OK")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                    Text("\(entry.monitors.count) servizi UP")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(problemMonitors.prefix(4)) { monitor in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(monitor.isDown ? Color.red : Color.yellow)
                                .frame(width: 6, height: 6)
                            Text(shortName(monitor.name))
                                .font(.caption2)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            Text(monitor.finalStatus)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(monitor.isDown ? .red : .yellow)
                        }
                    }
                    if problemMonitors.count > 4 {
                        Text("+\(problemMonitors.count - 4) altri")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            // Header
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
                HStack {
                    Spacer()
                    Text("Caricamento...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(sortedMonitors.prefix(8)) { monitor in
                    HStack(spacing: 6) {
                        Text(shortName(monitor.name))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Sonde compatte
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
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sortedMonitors: [WidgetMonitor] {
        entry.monitors.sorted { m1, m2 in
            rank(m1) > rank(m2)
        }
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

// MARK: - Probe Dots (4 pallini compatti)

private struct ProbeDotsView: View {
    let monitor: WidgetMonitor

    var body: some View {
        HStack(spacing: 2) {
            Circle().fill(monitor.k1 == "UP" ? Color.green : Color.red).frame(width: 5, height: 5)
            Circle().fill(monitor.k2 == "UP" ? Color.green : Color.red).frame(width: 5, height: 5)
            Circle().fill(monitor.k3 == "UP" ? Color.green : Color.red).frame(width: 5, height: 5)
            Circle().fill(monitor.n1 == "UP" ? Color.green : Color.red).frame(width: 5, height: 5)
        }
    }
}

// MARK: - Helper

/// Accorcia il nome rimuovendo il prefisso "INVA - "
private func shortName(_ name: String) -> String {
    name.replacingOccurrences(of: "INVA - ", with: "")
}

// MARK: - Color hex (duplicato per il widget target)

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
    DashboardEntry(date: Date(), globalState: "GREEN", monitors: [], downCount: 0, mismatchCount: 0, isPlaceholder: false)
}

#Preview("Medium", as: .systemMedium) {
    UptimeDashboardWidget()
} timeline: {
    DashboardEntry(date: Date(), globalState: "YELLOW", monitors: [
        WidgetMonitor(name: "INVA - www.regione.vda.it", k1: "UP", k2: "UP", k3: "UP", n1: "DOWN", finalStatus: "UP"),
    ], downCount: 0, mismatchCount: 1, isPlaceholder: false)
}
#endif
