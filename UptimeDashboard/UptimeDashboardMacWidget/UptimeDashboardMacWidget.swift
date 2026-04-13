import WidgetKit
import SwiftUI

// MARK: - Modello e API (identico al widget iOS)

struct MacWidgetMonitor: Identifiable {
    let id = UUID()
    let name: String
    let k1: String
    let k2: String
    let k3: String
    let n1: String
    let finalStatus: String
    var isDown: Bool { finalStatus == "DOWN" }
    var isMismatch: Bool { !isDown && Set([k1, k2, k3, n1]).count > 1 }
    var isUp: Bool { !isDown && !isMismatch }
}

struct MacWidgetEntry: TimelineEntry {
    let date: Date
    let globalState: String
    let monitors: [MacWidgetMonitor]
    let downCount: Int
    let mismatchCount: Int
    let isPlaceholder: Bool

    static var placeholder: MacWidgetEntry {
        MacWidgetEntry(date: Date(), globalState: "GREEN", monitors: [],
                       downCount: 0, mismatchCount: 0, isPlaceholder: true)
    }
}

struct MacWidgetAPIClient {
    static func fetch() async -> MacWidgetEntry {
        guard let baseURL = Bundle.main.object(forInfoDictionaryKey: "BACKEND_BASE_URL") as? String,
              let token = Bundle.main.object(forInfoDictionaryKey: "WATCH_API_TOKEN") as? String,
              let url = URL(string: "\(baseURL)/api/watch-data") else {
            return .placeholder
        }
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Watch-Token")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return .placeholder }

            let globalState = json["global_state"] as? String ?? "GREEN"
            let monitors: [MacWidgetMonitor] = items.compactMap { dict in
                guard let name = dict["name"] as? String,
                      let k1 = dict["k1"] as? String, let k2 = dict["k2"] as? String,
                      let k3 = dict["k3"] as? String, let n1 = dict["n1"] as? String,
                      let f = dict["final"] as? String else { return nil }
                return MacWidgetMonitor(name: name, k1: k1, k2: k2, k3: k3, n1: n1, finalStatus: f)
            }
            return MacWidgetEntry(date: Date(), globalState: globalState, monitors: monitors,
                                  downCount: monitors.filter(\.isDown).count,
                                  mismatchCount: monitors.filter(\.isMismatch).count,
                                  isPlaceholder: false)
        } catch { return .placeholder }
    }
}

struct MacWidgetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacWidgetEntry { .placeholder }
    func getSnapshot(in context: Context, completion: @escaping (MacWidgetEntry) -> Void) {
        Task { completion(await MacWidgetAPIClient.fetch()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MacWidgetEntry>) -> Void) {
        Task {
            let entry = await MacWidgetAPIClient.fetch()
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date)!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

// MARK: - Color hex

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6: (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8: (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default: (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Widget

struct UptimeDashboardMacWidget: Widget {
    let kind = "UptimeDashboardMacWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MacWidgetTimelineProvider()) { entry in
            MacWidgetEntryView(entry: entry)
                .containerBackground(Color(hex: "#141c2b"), for: .widget)
        }
        .configurationDisplayName("INVA Dashboard")
        .description("Stato dei servizi monitorati")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct MacWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: MacWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall: MacSmallWidgetView(entry: entry)
        case .systemMedium: MacMediumWidgetView(entry: entry)
        case .systemLarge: MacLargeWidgetView(entry: entry)
        default: MacSmallWidgetView(entry: entry)
        }
    }
}

struct MacSmallWidgetView: View {
    let entry: MacWidgetEntry
    var body: some View {
        VStack(spacing: 8) {
            Circle().fill(ledColor).frame(width: 40, height: 40)
                .shadow(color: ledColor.opacity(0.6), radius: 8)
            Text("INVA").font(.caption.bold()).foregroundColor(.white)
            if entry.isPlaceholder {
                Text("Caricamento...").font(.caption2).foregroundColor(.secondary)
            } else if entry.downCount > 0 {
                Text("\(entry.downCount) DOWN").font(.caption.bold()).foregroundColor(.red)
            } else if entry.mismatchCount > 0 {
                Text("\(entry.mismatchCount) Mismatch").font(.caption.bold()).foregroundColor(.yellow)
            } else {
                Text("Tutto OK").font(.caption.bold()).foregroundColor(.green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var ledColor: Color {
        switch entry.globalState {
        case "RED": return .red; case "YELLOW": return .yellow; default: return .green
        }
    }
}

private func shortName(_ name: String) -> String {
    name.replacingOccurrences(of: "INVA - ", with: "")
}

struct MacMediumWidgetView: View {
    let entry: MacWidgetEntry
    private var sorted: [MacWidgetMonitor] {
        entry.monitors.sorted { r($0) > r($1) }
    }
    private func r(_ m: MacWidgetMonitor) -> Int { m.isDown ? 2 : m.isMismatch ? 1 : 0 }
    private func sc(_ m: MacWidgetMonitor) -> Color { m.isDown ? .red : m.isMismatch ? .yellow : .green }
    private var ledColor: Color {
        switch entry.globalState { case "RED": return .red; case "YELLOW": return .yellow; default: return .green }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(ledColor).frame(width: 14, height: 14)
                Text("INVA Dashboard").font(.caption.bold()).foregroundColor(.white)
                Spacer()
                if !entry.isPlaceholder { Text(entry.date, style: .time).font(.system(size: 9)).foregroundColor(.secondary) }
            }.padding(.bottom, 2)
            if entry.isPlaceholder {
                Spacer(); HStack { Spacer(); Text("Caricamento...").font(.caption).foregroundColor(.secondary); Spacer() }; Spacer()
            } else {
                ForEach(sorted.prefix(5)) { m in
                    HStack(spacing: 6) {
                        Text(shortName(m.name)).font(.system(size: 11, weight: .medium)).foregroundColor(.white).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 2) {
                            Circle().fill(m.k1 == "UP" ? Color.green : .red).frame(width: 5, height: 5)
                            Circle().fill(m.k2 == "UP" ? Color.green : .red).frame(width: 5, height: 5)
                            Circle().fill(m.k3 == "UP" ? Color.green : .red).frame(width: 5, height: 5)
                            Circle().fill(m.n1 == "UP" ? Color.green : .red).frame(width: 5, height: 5)
                        }
                        Text(m.finalStatus).font(.system(size: 9, weight: .bold)).foregroundColor(sc(m)).frame(width: 32)
                    }.padding(.vertical, 1)
                }
                if entry.monitors.count > 5 { Text("+\(entry.monitors.count - 5) altri").font(.system(size: 9)).foregroundColor(.secondary) }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacLargeWidgetView: View {
    let entry: MacWidgetEntry
    private var sorted: [MacWidgetMonitor] {
        entry.monitors.sorted { r($0) > r($1) }
    }
    private func r(_ m: MacWidgetMonitor) -> Int { m.isDown ? 2 : m.isMismatch ? 1 : 0 }
    private func sc(_ m: MacWidgetMonitor) -> Color { m.isDown ? .red : m.isMismatch ? .yellow : .green }
    private var ledColor: Color {
        switch entry.globalState { case "RED": return .red; case "YELLOW": return .yellow; default: return .green }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(ledColor).frame(width: 14, height: 14)
                Text("INVA Dashboard").font(.caption.bold()).foregroundColor(.white)
                Spacer()
                if !entry.isPlaceholder { Text(entry.date, style: .time).font(.system(size: 9)).foregroundColor(.secondary) }
            }.padding(.bottom, 2)
            if entry.isPlaceholder {
                Spacer(); HStack { Spacer(); Text("Caricamento...").font(.caption).foregroundColor(.secondary); Spacer() }; Spacer()
            } else {
                ForEach(sorted.prefix(10)) { m in
                    HStack(spacing: 6) {
                        Text(shortName(m.name)).font(.system(size: 11, weight: .medium)).foregroundColor(.white).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 2) {
                            Circle().fill(m.k1 == "UP" ? Color.green : .red).frame(width: 5, height: 5)
                            Circle().fill(m.k2 == "UP" ? Color.green : .red).frame(width: 5, height: 5)
                            Circle().fill(m.k3 == "UP" ? Color.green : .red).frame(width: 5, height: 5)
                            Circle().fill(m.n1 == "UP" ? Color.green : .red).frame(width: 5, height: 5)
                        }
                        Text(m.finalStatus).font(.system(size: 9, weight: .bold)).foregroundColor(sc(m)).frame(width: 32)
                    }.padding(.vertical, 1)
                }
                if entry.monitors.count > 10 { Text("+\(entry.monitors.count - 10) altri").font(.system(size: 9)).foregroundColor(.secondary) }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
