import WidgetKit
import SwiftUI

// MARK: - Data Model

struct WidgetMonitor: Identifiable {
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

struct DashboardEntry: TimelineEntry {
    let date: Date
    let globalState: String
    let monitors: [WidgetMonitor]
    let downCount: Int
    let mismatchCount: Int
    let sensorAlerts: SensorAlerts?
    let sensorError: Bool
    let isPlaceholder: Bool

    static var placeholder: DashboardEntry {
        DashboardEntry(
            date: Date(),
            globalState: "GREEN",
            monitors: [],
            downCount: 0,
            mismatchCount: 0,
            sensorAlerts: nil,
            sensorError: false,
            isPlaceholder: true
        )
    }
}

// MARK: - Sensor Alerts (Widget-local model matching backend JSON)

struct SensorAlerts: Codable, Equatable {
    let warningCount: Int
    let criticalCount: Int

    enum CodingKeys: String, CodingKey {
        case warningCount = "warning_count"
        case criticalCount = "critical_count"
    }

    var totalCount: Int { warningCount + criticalCount }
    var hasAlerts: Bool { totalCount > 0 }
    var hasCritical: Bool { criticalCount > 0 }
}

// MARK: - API Fetch

struct WidgetAPIClient {
    static func fetch() async -> DashboardEntry {
        guard let baseURL = Bundle.main.object(forInfoDictionaryKey: "BACKEND_BASE_URL") as? String,
              let token = Bundle.main.object(forInfoDictionaryKey: "WATCH_API_TOKEN") as? String,
              let url = URL(string: "\(baseURL)/api/watch-data") else {
            return DashboardEntry.placeholder
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Watch-Token")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                return DashboardEntry.placeholder
            }

            let globalState = json["global_state"] as? String ?? "GREEN"
            let monitors: [WidgetMonitor] = items.compactMap { dict in
                guard let name = dict["name"] as? String,
                      let k1 = dict["k1"] as? String,
                      let k2 = dict["k2"] as? String,
                      let k3 = dict["k3"] as? String,
                      let n1 = dict["n1"] as? String,
                      let final_ = dict["final"] as? String else { return nil }
                let u1 = dict["u1"] as? String ?? "UP"
                return WidgetMonitor(name: name, k1: k1, k2: k2, k3: k3, n1: n1, u1: u1, finalStatus: final_)
            }

            // Parse sensor alerts from response
            let sensorAlerts: SensorAlerts?
            if let alertsDict = json["sensor_alerts"] as? [String: Int] {
                sensorAlerts = SensorAlerts(
                    warningCount: alertsDict["warning_count"] ?? 0,
                    criticalCount: alertsDict["critical_count"] ?? 0
                )
            } else {
                sensorAlerts = nil
            }
            let sensorError = json["sensor_error"] != nil

            return DashboardEntry(
                date: Date(),
                globalState: globalState,
                monitors: monitors,
                downCount: monitors.filter(\.isDown).count,
                mismatchCount: monitors.filter(\.isMismatch).count,
                sensorAlerts: sensorAlerts,
                sensorError: sensorError,
                isPlaceholder: false
            )
        } catch {
            return DashboardEntry.placeholder
        }
    }
}

// MARK: - Timeline Provider

struct DashboardTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DashboardEntry) -> Void) {
        Task {
            let entry = await WidgetAPIClient.fetch()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardEntry>) -> Void) {
        Task {
            let entry = await WidgetAPIClient.fetch()
            // Aggiorna ogni 15 minuti (il minimo consentito da WidgetKit)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
}
