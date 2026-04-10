// Feature: ios-native-app
// Requisiti: 3.1, 3.4, 3.6, 4.2, 4.4, 6.1, 6.2, 6.3, 6.4, 7.2, 7.3, 7.4

import Foundation
import SwiftUI
import Combine

// MARK: - DashboardViewModel

@MainActor
final class DashboardViewModel: ObservableObject {

    @Published var items: [MonitorItem] = []
    @Published var globalState: GlobalState = .green
    @Published var isOnlyDownFilter: Bool = false
    @Published var lastUpdated: Date? = nil
    @Published var isStale: Bool = false

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

    /// LED color reflecting the current global state.
    var ledColor: Color {
        globalState.color
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
        } catch {
            // Preserve previous data, mark as stale
            isStale = true
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
    func applySortOrder(_ order: SortOrder) {
        switch order {
        case .severity:
            items.sort { $0.severityRank > $1.severityRank }
        case .alphabetical:
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .globalState:
            items.sort { globalStateRank($0.rowColor) > globalStateRank($1.rowColor) }
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
}
