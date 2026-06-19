import WidgetKit
import SwiftUI

// MARK: - Data Model

struct MacWidgetMonitor: Identifiable {
    let id = UUID()
    let name: String
    let k1: String
    let k2: String
    let k3: String
    let n1: String
    let u1: String
    let finalStatus: String

    var isDown: Bool { finalStatus == "DOWN" }
    var isMismatch: Bool { !isDown && Set([k1, k2, k3, n1, u1]).count > 1 }
    var isUp: Bool { !isDown && !isMismatch }
}

struct MacDashboardEntry: TimelineEntry {
    let date: Date
    let globalState: String
    let monitors: [MacWidgetMonitor]
    let downCount: Int
    let mismatchCount: Int
    let temperatureCritical: Int
    let powerCritical: Int
    let upsCritical: Int
    let generatorCritical: Int
    let sensorError: Bool
    let isPlaceholder: Bool

    static var placeholder: MacDashboardEntry {
        MacDashboardEntry(
            date: Date(),
            globalState: "GREEN",
            monitors: [],
            downCount: 0,
            mismatchCount: 0,
            temperatureCritical: 0,
            powerCritical: 0,
            upsCritical: 0,
            generatorCritical: 0,
            sensorError: false,
            isPlaceholder: true
        )
    }
}

// MARK: - API Fetch

struct MacWidgetAPIClient {
    static func fetch() async -> MacDashboardEntry {
        guard let baseURL = Bundle.main.object(forInfoDictionaryKey: "BACKEND_BASE_URL") as? String,
              let token = Bundle.main.object(forInfoDictionaryKey: "WATCH_API_TOKEN") as? String,
              let url = URL(string: "\(baseURL)/api/watch-data") else {
            return MacDashboardEntry.placeholder
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Watch-Token")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                return MacDashboardEntry.placeholder
            }

            let globalState = json["global_state"] as? String ?? "GREEN"
            let monitors: [MacWidgetMonitor] = items.compactMap { dict in
                guard let name = dict["name"] as? String,
                      let k1 = dict["k1"] as? String,
                      let k2 = dict["k2"] as? String,
                      let k3 = dict["k3"] as? String,
                      let n1 = dict["n1"] as? String,
                      let final_ = dict["final"] as? String else { return nil }
                let u1 = dict["u1"] as? String ?? "UP"
                return MacWidgetMonitor(name: name, k1: k1, k2: k2, k3: k3, n1: n1, u1: u1, finalStatus: final_)
            }

            // Parse sensors and count critical per category
            var tempCritical = 0
            var powerCritical = 0
            var upsCritical = 0
            var genCritical = 0

            if let sensorsArray = json["sensors"] as? [[String: Any]] {
                for sensor in sensorsArray {
                    let status = sensor["status"] as? String ?? "normal"
                    guard status == "critical" else { continue }
                    let category = sensor["category"] as? String ?? ""
                    switch category {
                    case "temperature": tempCritical += 1
                    case "power": powerCritical += 1
                    case "ups": upsCritical += 1
                    case "generator": genCritical += 1
                    default: break
                    }
                }
            }

            let sensorError = json["sensor_error"] != nil

            return MacDashboardEntry(
                date: Date(),
                globalState: globalState,
                monitors: monitors,
                downCount: monitors.filter(\.isDown).count,
                mismatchCount: monitors.filter(\.isMismatch).count,
                temperatureCritical: tempCritical,
                powerCritical: powerCritical,
                upsCritical: upsCritical,
                generatorCritical: genCritical,
                sensorError: sensorError,
                isPlaceholder: false
            )
        } catch {
            return MacDashboardEntry.placeholder
        }
    }
}

// MARK: - Timeline Provider

struct MacDashboardTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacDashboardEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (MacDashboardEntry) -> Void) {
        Task {
            let entry = await MacWidgetAPIClient.fetch()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacDashboardEntry>) -> Void) {
        Task {
            let entry = await MacWidgetAPIClient.fetch()
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
}

// MARK: - Widget Definition

struct UptimeDashboardMacWidget: Widget {
    let kind = "UptimeDashboardMacWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MacDashboardTimelineProvider()) { entry in
            MacWidgetEntryView(entry: entry)
                .containerBackground(Color(hex: "#141c2b"), for: .widget)
        }
        .configurationDisplayName("INVA Dashboard")
        .description("Stato dei servizi monitorati")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry View (router per dimensione)

struct MacWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: MacDashboardEntry

    var body: some View {
        switch family {
        case .systemSmall:
            MacSmallWidgetView(entry: entry)
        case .systemMedium:
            MacMediumWidgetView(entry: entry)
        case .systemLarge:
            MacLargeWidgetView(entry: entry)
        default:
            MacSmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget: 3 macro areas compact

struct MacSmallWidgetView: View {
    let entry: MacDashboardEntry

    var body: some View {
        VStack(spacing: 6) {
            Text("INVA")
                .font(.caption2.bold())
                .foregroundColor(.white)

            if entry.isPlaceholder {
                Text("Caricamento...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                MacMacroRow(icon: "globe", title: "Portali", color: portalsColor, detail: portalsDetail)
                MacMacroRow(icon: "thermometer.medium", title: "Temp", color: temperatureColor, detail: temperatureDetail)
                MacMacroRow(icon: "bolt.fill", title: "Potenza", color: powerColor, detail: powerDetail)
                MacMacroRow(icon: "battery.75percent", title: "UPS", color: upsColor, detail: upsDetail)
                MacMacroRow(icon: "fuelpump.fill", title: "GE", color: generatorColor, detail: generatorDetail)
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

// MARK: - Medium Widget: 3 macro areas

struct MacMediumWidgetView: View {
    let entry: MacDashboardEntry

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
                HStack(spacing: 8) {
                    MacMacroCard(icon: "globe", title: "Portali", color: portalsColor, subtitle: portalsSubtitle)
                    MacMacroCard(icon: "thermometer.medium", title: "Temp", color: temperatureColor, subtitle: temperatureSubtitle)
                    MacMacroCard(icon: "bolt.fill", title: "Potenza", color: powerColor, subtitle: powerSubtitle)
                    MacMacroCard(icon: "battery.75percent", title: "UPS", color: upsColor, subtitle: upsSubtitle)
                    MacMacroCard(icon: "fuelpump.fill", title: "GE", color: generatorColor, subtitle: generatorSubtitle)
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
        let total = entry.monitors.count
        if entry.downCount > 0 { return "\(entry.downCount) DOWN / \(total)" }
        if entry.mismatchCount > 0 { return "\(entry.mismatchCount) ⚠ / \(total)" }
        return "OK (\(total))"
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

// MARK: - Large Widget: 3 macro areas + top monitors

struct MacLargeWidgetView: View {
    let entry: MacDashboardEntry

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
            .padding(.bottom, 4)

            if entry.isPlaceholder {
                Spacer()
                HStack { Spacer(); Text("Caricamento...").font(.caption).foregroundColor(.secondary); Spacer() }
                Spacer()
            } else {
                HStack(spacing: 8) {
                    MacMacroCard(icon: "globe", title: "Portali", color: portalsColor, subtitle: portalsSubtitle)
                    MacMacroCard(icon: "thermometer.medium", title: "Temp", color: temperatureColor, subtitle: temperatureSubtitle)
                    MacMacroCard(icon: "bolt.fill", title: "Potenza", color: powerColor, subtitle: powerSubtitle)
                    MacMacroCard(icon: "battery.75percent", title: "UPS", color: upsColor, subtitle: upsSubtitle)
                    MacMacroCard(icon: "fuelpump.fill", title: "GE", color: generatorColor, subtitle: generatorSubtitle)
                }
                .padding(.bottom, 4)

                Divider().background(Color.white.opacity(0.2))

                ForEach(sortedMonitors.prefix(5)) { monitor in
                    MacWidgetMonitorRow(monitor: monitor)
                }

                if entry.monitors.count > 5 {
                    Text("+\(entry.monitors.count - 5) altri")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sortedMonitors: [MacWidgetMonitor] {
        entry.monitors.sorted { rank($0) > rank($1) }
    }

    private func rank(_ m: MacWidgetMonitor) -> Int {
        if m.isDown { return 2 }
        if m.isMismatch { return 1 }
        return 0
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
    private var temperatureSubtitle: String { entry.sensorError ? "—" : (entry.temperatureCritical > 0 ? "\(entry.temperatureCritical) ⚠" : "OK") }
    private var powerColor: Color { entry.powerCritical > 0 ? .red : .blue }
    private var powerSubtitle: String { entry.sensorError ? "—" : (entry.powerCritical > 0 ? "\(entry.powerCritical) ⚠" : "OK") }
    private var upsColor: Color { entry.upsCritical > 0 ? .red : .purple }
    private var upsSubtitle: String { entry.sensorError ? "—" : (entry.upsCritical > 0 ? "\(entry.upsCritical) ⚠" : "OK") }
    private var generatorColor: Color { entry.generatorCritical > 0 ? .red : .orange }
    private var generatorSubtitle: String { entry.sensorError ? "—" : (entry.generatorCritical > 0 ? "\(entry.generatorCritical) ⚠" : "OK") }
}

// MARK: - MacMacroRow (compact, for small widget)

private struct MacMacroRow: View {
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

// MARK: - MacMacroCard (for medium/large widget)

private struct MacMacroCard: View {
    let icon: String
    let title: String
    let color: Color
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 8))
                .foregroundColor(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Monitor Row (shared)

private struct MacWidgetMonitorRow: View {
    let monitor: MacWidgetMonitor

    var body: some View {
        HStack(spacing: 6) {
            Text(shortName(monitor.name))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            MacProbeDotsView(monitor: monitor)

            Text(monitor.finalStatus)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(statusColor)
                .frame(width: 32)
        }
        .padding(.vertical, 1)
    }

    private var statusColor: Color {
        if monitor.isDown { return .red }
        if monitor.isMismatch { return .yellow }
        return .green
    }
}

// MARK: - Probe Dots (5 pallini compatti)

private struct MacProbeDotsView: View {
    let monitor: MacWidgetMonitor

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

// MARK: - Color hex

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
