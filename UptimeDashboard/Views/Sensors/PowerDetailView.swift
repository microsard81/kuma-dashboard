// Feature: native-apps-sensor-integration

import SwiftUI

/// Detail view showing all power sensors with sparklines.
/// Swipe right on a sensor to enter reorder mode (drag & drop).
/// Order is persisted in UserDefaults.
struct PowerDetailView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var isReordering = false
    @State private var manualOrder: [SensorReading] = []

    private let orderKey = "sensor_order_power"

    private var displaySensors: [SensorReading] {
        if isReordering { return manualOrder }

        // Base order: saved custom order or default
        let saved = loadSavedOrder()
        var baseOrder: [SensorReading]
        if !saved.isEmpty {
            var ordered: [SensorReading] = []
            let sensorMap = Dictionary(uniqueKeysWithValues: viewModel.powerSensors.map { ($0.id, $0) })
            for id in saved {
                if let s = sensorMap[id] { ordered.append(s) }
            }
            for s in viewModel.powerSensors where !saved.contains(s.id) {
                ordered.append(s)
            }
            baseOrder = ordered
        } else {
            baseOrder = viewModel.powerSensors
        }

        // Stable sort: critical first, then warning, then normal — preserving relative order within each group
        guard let t = viewModel.sensorThresholds else { return baseOrder }
        let critical = baseOrder.filter { $0.alertStatus(thresholds: t) == .critical }
        let warning = baseOrder.filter { $0.alertStatus(thresholds: t) == .warning }
        let normal = baseOrder.filter { $0.alertStatus(thresholds: t) == .normal }
        return critical + warning + normal
    }

    private func severityRank(_ status: AlertStatus) -> Int {
        switch status {
        case .critical: return 2
        case .warning: return 1
        case .normal: return 0
        }
    }

    var body: some View {
        List {
            ForEach(displaySensors) { sensor in
                SensorCardView(
                    sensor: sensor,
                    thresholds: viewModel.sensorThresholds,
                    historyPoints: viewModel.sensorHistory[sensor.id] ?? []
                )
                .listRowSeparator(.visible)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if !isReordering {
                        Button {
                            manualOrder = displaySensors
                            withAnimation { isReordering = true }
                        } label: {
                            Label("Riordina", systemImage: "arrow.up.arrow.down")
                        }
                        .tint(.blue)
                    }
                }
            }
            .onMove { from, to in
                manualOrder.move(fromOffsets: from, toOffset: to)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, isReordering ? .constant(.active) : .constant(.inactive))
        .refreshable { await viewModel.refresh() }
        .navigationTitle("Potenza (kW)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isReordering {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Termina") {
                        saveOrder(manualOrder.map(\.id))
                        withAnimation { isReordering = false }
                    }
                    .bold()
                }
            }
        }
    }

    // MARK: - Persistence

    private func saveOrder(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: orderKey)
    }

    private func loadSavedOrder() -> [String] {
        UserDefaults.standard.stringArray(forKey: orderKey) ?? []
    }
}
