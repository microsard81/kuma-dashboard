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
    let temperatureCritical: Int
    let powerCritical: Int
    let upsCritical: Int
    let generatorCritical: Int
    let sensorError: Bool
    let isPlaceholder: Bool

    static var placeholder: DashboardEntry {
        DashboardEntry(
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

// MARK: - Sensor Category Status (per-category critical count)

struct CategoryStatus {
    let critical: Int
    var color: Color { critical > 0 ? .red : normalColor }
    let normalColor: Color
    var detail: String { critical > 0 ? "\(critical) ⚠" : "OK" }
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

            return DashboardEntry(
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
