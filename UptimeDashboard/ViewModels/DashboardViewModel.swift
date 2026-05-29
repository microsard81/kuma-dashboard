// Feature: ios-native-app
// Requisiti: 3.1, 3.4, 3.6, 4.2, 4.4, 6.1, 6.2, 6.3, 6.4, 7.2, 7.3, 7.4

import Foundation
import SwiftUI
import Combine
import WatchConnectivity

// MARK: - DashboardViewModel

@MainActor
final class DashboardViewModel: ObservableObject {

    @Published var items: [MonitorItem] = []
    @Published var globalState: GlobalState = .green
    @Published var isOnlyDownFilter: Bool = false
    @Published var lastUpdated: Date? = nil
    @Published var isStale: Bool = false

    // MARK: - Sensor properties
    @Published var sensors: [SensorReading] = []
    @Published var sensorThresholds: SensorThresholds?
    @Published var sensorHistory: [String: [SensorHistoryPoint]] = [:]
    @Published var sensorAlerts: SensorAlerts?
    @Published var sensorError: String?

    // MARK: - Computed properties

    /// Returns filtered items based on the current filter state.
    /// Includes both fully DOWN and mismatch (partially DOWN) items.
    var filteredItems: [MonitorItem] {
        isOnlyDownFilter ? items.filter { $0.rowColor == .red || $0.rowColor == .yellow } : items
    }

    /// Count of monitors currently in DOWN or mismatch state.
    var downCount: Int {
        items.filter { $0.rowColor == .red || $0.rowColor == .yellow }.count
    }

    /// Count of monitors completely DOWN (severity 2).
    var redCount: Int {
        items.filter { $0.rowColor == .red }.count
    }

    /// Count of monitors in mismatch state (severity 1).
    var mismatchCount: Int {
        items.filter { $0.rowColor == .yellow }.count
    }

    /// LED color reflecting the current global state.
    var ledColor: Color {
        globalState.color
    }

    /// Temperature sensors filtered from the full sensors array.
    var temperatureSensors: [SensorReading] {
        sensors.filter { $0.category == .temperature }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Power sensors filtered from the full sensors array.
    var powerSensors: [SensorReading] {
        sensors.filter { $0.category == .power }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Dependencies

    private let network: NetworkClientProtocol
    private var refreshTimer: Timer?
    private var currentSortOrder: SortOrder = .severity
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(network: NetworkClientProtocol) {
        self.network = network
    }

    // MARK: - Settings binding

    /// Subscribes to SettingsViewModel changes via Combine.
    func bindSettings(_ settings: SettingsViewModel) {
        settings.$sortOrder
            .receive(on: RunLoop.main)
            .sink { [weak self] order in
                self?.currentSortOrder = order
                self?.applySortOrder(order)
            }
            .store(in: &cancellables)

        settings.$refreshInterval
            .receive(on: RunLoop.main)
            .sink { [weak self] interval in
                self?.restartAutoRefresh(interval: interval)
            }
            .store(in: &cancellables)
    }

    // MARK: - refresh

    /// Fetches fresh dashboard data from the backend.
    /// On success: updates items (sorted by severity), globalState, lastUpdated, clears stale flag.
    /// On error: sets isStale = true, preserves previous data.
    func refresh() async {
        do {
            let response = try await network.fetchDashboardData()
            // Sort: DOWN (severityRank 2) first, then mismatch (1), then UP (0)
            let sorted = response.items.sorted { $0.severityRank > $1.severityRank }
            items = sorted
            applySortOrder(currentSortOrder)
            globalState = response.globalState
            lastUpdated = Date()
            isStale = false
            sendToWatch(items: sorted, globalState: response.globalState)
        } catch {
            // Preserve previous data, mark as stale
            isStale = true
        }

        // Fetch sensor data independently (graceful degradation)
        await fetchSensorData()
    }

    // MARK: - Sensor data fetching

    /// Fetches sensor data from `/api/inverter-data` using the authenticated session.
    /// On failure, sets sensorError and clears sensor data gracefully.
    private func fetchSensorData() async {
        do {
            let response = try await network.fetchSensorData()
            parseSensorPayload(data: response)
        } catch {
            sensorError = "Errore connessione sensori"
        }
    }

    /// Parses sensor fields from the `/api/inverter-data` JSON response.
    /// Missing fields are treated as empty (graceful degradation).
    private func parseSensorPayload(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sensorError = "Errore decodifica sensori"
            return
        }

        let decoder = JSONDecoder()

        // Parse sensors array
        if let sensorsArray = json["sensors"] {
            if let sensorsData = try? JSONSerialization.data(withJSONObject: sensorsArray),
               let decoded = try? decoder.decode([SensorReading].self, from: sensorsData) {
                sensors = decoded
            } else {
                sensors = []
            }
        } else {
            sensors = []
        }

        // Parse thresholds
        if let thresholdsObj = json["thresholds"] {
            if let thresholdsData = try? JSONSerialization.data(withJSONObject: thresholdsObj),
               let decoded = try? decoder.decode(SensorThresholds.self, from: thresholdsData) {
                sensorThresholds = decoded
            } else {
                sensorThresholds = nil
            }
        } else {
            sensorThresholds = nil
        }

        // Parse history (key is "history" from /api/inverter-data, or "sensor_history" from /api/watch-data)
        let historyObj = json["history"] ?? json["sensor_history"]
        if let historyObj = historyObj {
            if let historyData = try? JSONSerialization.data(withJSONObject: historyObj),
               let decoded = try? decoder.decode([String: [SensorHistoryPoint]].self, from: historyData) {
                sensorHistory = decoded
            } else {
                sensorHistory = [:]
            }
        } else {
            sensorHistory = [:]
        }

        // Compute sensor_alerts client-side from sensors + thresholds
        if let thresholds = sensorThresholds {
            var warningCount = 0
            var criticalCount = 0
            for sensor in sensors {
                let status = sensor.alertStatus(thresholds: thresholds)
                if status == .critical { criticalCount += 1 }
                else if status == .warning { warningCount += 1 }
            }
            sensorAlerts = SensorAlerts(warningCount: warningCount, criticalCount: criticalCount)
        } else {
            sensorAlerts = nil
        }

        // Parse error (key is "error" from /api/inverter-data, or "sensor_error" from /api/watch-data)
        if let errorStr = json["error"] as? String {
            sensorError = errorStr
        } else if let errorStr = json["sensor_error"] as? String {
            sensorError = errorStr
        } else {
            sensorError = nil
        }
    }

    // MARK: - Auto-refresh

    /// Starts a repeating timer that calls refresh() every 10 seconds.
    func startAutoRefresh() {
        stopAutoRefresh()
        // Trigger an immediate refresh
        Task { await refresh() }
        // Schedule repeating timer on the main run loop
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh() }
        }
    }

    /// Invalidates the auto-refresh timer.
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Riavvia auto-refresh con nuovo intervallo.
    func restartAutoRefresh(interval: RefreshInterval) {
        stopAutoRefresh()
        guard let seconds = interval.seconds else { return }
        Task { await refresh() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh() }
        }
    }

    // MARK: - Sorting

    /// Riordina items secondo il criterio specificato.
    /// Per severity e globalState, gli elementi all'interno di ogni gruppo
    /// sono sempre ordinati alfabeticamente.
    func applySortOrder(_ order: SortOrder) {
        switch order {
        case .severity:
            items.sort {
                if $0.severityRank != $1.severityRank {
                    return $0.severityRank > $1.severityRank
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .alphabetical:
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .globalState:
            items.sort {
                let rank0 = globalStateRank($0.rowColor)
                let rank1 = globalStateRank($1.rowColor)
                if rank0 != rank1 {
                    return rank0 > rank1
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    /// Maps a RowColor to an integer rank for sorting (red highest).
    private func globalStateRank(_ color: RowColor) -> Int {
        switch color {
        case .red: return 2
        case .yellow: return 1
        case .green: return 0
        }
    }

    // MARK: - WatchConnectivity

    /// Invia i dati della dashboard all'Apple Watch via applicationContext.
    private func sendToWatch(items: [MonitorItem], globalState: GlobalState) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired else { return }

        let itemDicts: [[String: Any]] = items.map { item in
            [
                "name": item.name,
                "k1": item.k1.rawValue,
                "k2": item.k2.rawValue,
                "k3": item.k3.rawValue,
                "n1": item.n1.rawValue,
                "u1": item.u1.rawValue,
                "final": item.final.rawValue,
            ]
        }

        let context: [String: Any] = [
            "items": itemDicts,
            "global_state": globalState.rawValue,
        ]

        try? session.updateApplicationContext(context)
    }
}
