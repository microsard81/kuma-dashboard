//
//  UptimeDashboardWatchWidget.swift
//  UptimeDashboardWatchWidget
//
//  Created by Luca Carta on 17/04/2026.
//

import WidgetKit
import SwiftUI

// MARK: - Data Model

struct WatchWidgetEntry: TimelineEntry {
    let date: Date
    let globalState: String
    let totalCount: Int
    let downCount: Int
    let mismatchCount: Int
    let sensorAlertCount: Int       // warning + critical total
    let sensorAlertSeverity: String // "none", "warning", "critical"
    let isPlaceholder: Bool

    static var placeholder: WatchWidgetEntry {
        WatchWidgetEntry(
            date: Date(),
            globalState: "GREEN",
            totalCount: 0,
            downCount: 0,
            mismatchCount: 0,
            sensorAlertCount: 0,
            sensorAlertSeverity: "none",
            isPlaceholder: true
        )
    }
}

// MARK: - API Fetch

struct WatchWidgetAPIClient {
    static func fetch() async -> WatchWidgetEntry {
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
                  let items = json["items"] as? [[String: Any]] else {
                return .placeholder
            }

            let globalState = json["global_state"] as? String ?? "GREEN"
            var downCount = 0
            var mismatchCount = 0

            for item in items {
                guard let final_ = item["final"] as? String else { continue }
                if final_ == "DOWN" {
                    downCount += 1
                } else {
                    let k1 = item["k1"] as? String ?? "UP"
                    let k2 = item["k2"] as? String ?? "UP"
                    let k3 = item["k3"] as? String ?? "UP"
                    let n1 = item["n1"] as? String ?? "UP"
                    let u1 = item["u1"] as? String ?? "UP"
                    if Set([k1, k2, k3, n1, u1]).count > 1 {
                        mismatchCount += 1
                    }
                }
            }

            // Parse sensor alerts
            let sensorAlertCount: Int
            let sensorAlertSeverity: String
            if let alertsDict = json["sensor_alerts"] as? [String: Any] {
                let warningCount = alertsDict["warning_count"] as? Int ?? 0
                let criticalCount = alertsDict["critical_count"] as? Int ?? 0
                sensorAlertCount = warningCount + criticalCount
                sensorAlertSeverity = criticalCount > 0 ? "critical" : (warningCount > 0 ? "warning" : "none")
            } else {
                sensorAlertCount = 0
                sensorAlertSeverity = "none"
            }

            return WatchWidgetEntry(
                date: Date(),
                globalState: globalState,
                totalCount: items.count,
                downCount: downCount,
                mismatchCount: mismatchCount,
                sensorAlertCount: sensorAlertCount,
                sensorAlertSeverity: sensorAlertSeverity,
                isPlaceholder: false
            )
        } catch {
            return .placeholder
        }
    }
}

// MARK: - Timeline Provider

struct WatchWidgetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchWidgetEntry) -> Void) {
        Task {
            let entry = await WatchWidgetAPIClient.fetch()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchWidgetEntry>) -> Void) {
        Task {
            let entry = await WatchWidgetAPIClient.fetch()
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
}
