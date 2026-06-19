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

// MARK: - Small Widget: 5 righe stato compatto

struct SmallWidgetView: View {
    let entry: DashboardEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
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
                MacroRow(icon: "globe", title: "Portali", color: portalsColor, detail: portalsDetail)
                MacroRow(icon: "thermometer.medium", title: "Temperatura", color: temperatureColor, detail: temperatureDetail)
                MacroRow(icon: "bolt.fill", title: "Potenza", color: powerColor, detail: powerDetail)
                MacroRow(icon: "battery.75percent", title: "UPS", color: upsColor, detail: upsDetail)
                MacroRow(icon: "fuelpump.fill", title: "Generatori", color: generatorColor, detail: generatorDetail)
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
        return "OK"
    }
    private var temperatureColor: Color { entry.temperatureCritical > 0 ? .red : .orange }
    private var temperatureDetail: String { entry.sensorError ? "—" : (entry.temperatureCritical > 0 ? "\(entry.temperatureCritical) ⚠" : "OK") }
    private var powerColor: Color { entry.powerCritical > 0 ? .red : .blue }
    private var powerDetail: String { entry.sensorError ? "—" : (entry.powerCritical > 0 ? "\(entry.powerCritical) ⚠" : "OK") }
    private var upsColor: Color { entry.upsCritical > 0 ? .red : .purple }
    private var upsDetail: String { entry.sensorError ? "—" : (entry.upsCritical > 0 ? "\(entry.upsCritical) ⚠" : "OK") }
    private var generatorColor: Color { entry.generatorCritical > 0 ? .red : .orange }
    private var generatorDetail: String { entry.sensorError ? "—" : (entry.generatorCritical > 0 ? "\(entry.generatorCritical) ⚠" : "OK") }
}

// MARK: - Medium Widget: 5 card affiancate

struct MediumWidgetView: View {
    let entry: DashboardEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Dashboard INVA")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                Spacer()
                if !entry.isPlaceholder {
                    Text(entry.date, style: .time)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            if entry.isPlaceholder {
                Spacer()
                HStack { Spacer(); Text("Caricamento...").font(.caption).foregroundColor(.secondary); Spacer() }
                Spacer()
            } else {
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    MacroCard(icon: "globe", title: "Portali", color: portalsColor, subtitle: portalsSubtitle)
                    MacroCard(icon: "thermometer.medium", title: "Temp", color: temperatureColor, subtitle: temperatureSubtitle)
                    MacroCard(icon: "bolt.fill", title: "Potenza", color: powerColor, subtitle: powerSubtitle)
                    MacroCard(icon: "battery.75percent", title: "UPS", color: upsColor, subtitle: upsSubtitle)
                    MacroCard(icon: "fuelpump.fill", title: "GE", color: generatorColor, subtitle: generatorSubtitle)
                }
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
    private var portalsSubtitle: String {
        if entry.downCount > 0 { return "\(entry.downCount) DOWN" }
        if entry.mismatchCount > 0 { return "\(entry.mismatchCount) ⚠" }
        return "OK (\(entry.monitors.count))"
    }
    private var temperatureColor: Color { entry.temperatureCritical > 0 ? .red : .orange }
    private var temperatureSubtitle: String { entry.sensorError ? "Errore" : (entry.temperatureCritical > 0 ? "\(entry.temperatureCritical) ⚠" : "OK") }
    private var powerColor: Color { entry.powerCritical > 0 ? .red : .blue }
    private var powerSubtitle: String { entry.sensorError ? "Errore" : (entry.powerCritical > 0 ? "\(entry.powerCritical) ⚠" : "OK") }
    private var upsColor: Color { entry.upsCritical > 0 ? .red : .purple }
    private var upsSubtitle: String { entry.sensorError ? "Errore" : (entry.upsCritical > 0 ? "\(entry.upsCritical) ⚠" : "OK") }
    private var generatorColor: Color { entry.generatorCritical > 0 ? .red : .orange }
    private var generatorSubtitle: String { entry.sensorError ? "Errore" : (entry.generatorCritical > 0 ? "\(entry.generatorCritical) ⚠" : "OK") }
}

// MARK: - Large Widget: 5 card + lista portali

struct LargeWidgetView: View {
    let entry: DashboardEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Dashboard INVA")
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
                // 5 card
                HStack(spacing: 6) {
                    MacroCard(icon: "globe", title: "Portali", color: portalsColor, subtitle: portalsSubtitle)
                    MacroCard(icon: "thermometer.medium", title: "Temp", color: temperatureColor, subtitle: temperatureSubtitle)
                    MacroCard(icon: "bolt.fill", title: "Potenza", color: powerColor, subtitle: powerSubtitle)
                    MacroCard(icon: "battery.75percent", title: "UPS", color: upsColor, subtitle: upsSubtitle)
                    MacroCard(icon: "fuelpump.fill", title: "GE", color: generatorColor, subtitle: generatorSubtitle)
                }
                .padding(.bottom, 4)

                Divider().background(Color.white.opacity(0.2))

                // Monitor list (portali)
                ForEach(sortedMonitors) { monitor in
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

    private var portalsColor: Color {
        if entry.downCount > 0 { return .red }
        if entry.mismatchCount > 0 { return .yellow }
        return .green
    }
    private var portalsSubtitle: String {
        if entry.downCount > 0 { return "\(entry.downCount) DOWN" }
        if entry.mismatchCount > 0 { return "\(entry.mismatchCount) ⚠" }
        return "OK"
    }
    private var temperatureColor: Color { entry.temperatureCritical > 0 ? .red : .orange }
    private var temperatureSubtitle: String { entry.sensorError ? "—" : (entry.temperatureCritical > 0 ? "\(entry.temperatureCritical) ⚠" : "OK") }
    private var powerColor: Color { entry.powerCritical > 0 ? .red : .blue }
    private var powerSubtitle: String { entry.sensorError ? "—" : (entry.powerCritical > 0 ? "\(entry.powerCritical) ⚠" : "OK") }
    private var upsColor: Color { entry.upsCritical > 0 ? .red : .purple }
    private var upsSubtitle: String { entry.sensorError ? "—" : (entry.upsCritical > 0 ? "\(entry.upsCritical) ⚠" : "OK") }
    private var generatorColor: Color { entry.generatorCritical > 0 ? .red : .orange }
    private var generatorSubtitle: String { entry.sensorError ? "—" : (entry.generatorCritical > 0 ? "\(entry.generatorCritical) ⚠" : "OK") }
}

// MARK: - MacroCard (quadrato per medium/large)

private struct MacroCard: View {
    let icon: String
    let title: String
    let color: Color
    let subtitle: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 7))
                .foregroundColor(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(6)
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
                .frame(width: 7, height: 7)
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Text(detail)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(color)
        }
    }
}

// MARK: - ProbeDotsView (5 pallini sonda per monitor)

private struct ProbeDotsView: View {
    let monitor: WidgetMonitor

    var body: some View {
        HStack(spacing: 2) {
            Circle().fill(monitor.k1 == "DOWN" ? Color.red : Color.green).frame(width: 5, height: 5)
            Circle().fill(monitor.k2 == "DOWN" ? Color.red : Color.green).frame(width: 5, height: 5)
            Circle().fill(monitor.k3 == "DOWN" ? Color.red : Color.green).frame(width: 5, height: 5)
            Circle().fill(monitor.n1 == "DOWN" ? Color.red : Color.green).frame(width: 5, height: 5)
            Circle().fill(monitor.u1 == "DOWN" ? Color.red : Color.green).frame(width: 5, height: 5)
        }
    }
}

// MARK: - Helpers

private func shortName(_ name: String) -> String {
    // Rimuovi prefisso comune "www." se presente
    if name.hasPrefix("www.") { return String(name.dropFirst(4)) }
    return name
}

// MARK: - Color(hex:)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        r = Double((int >> 16) & 0xFF) / 255
        g = Double((int >> 8) & 0xFF) / 255
        b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
