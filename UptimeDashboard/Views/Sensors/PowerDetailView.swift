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
        let saved = loadSavedOrder()
        if !saved.isEmpty {
            var ordered: [SensorReading] = []
            let sensorMap = Dictionary(uniqueKeysWithValues: viewModel.powerSensors.map { ($0.id, $0) })
            for id in saved {
                if let s = sensorMap[id] { ordered.append(s) }
            }
            for s in viewModel.powerSensors where !saved.contains(s.id) {
                ordered.append(s)
            }
            return ordered
        }
        guard let t = viewModel.sensorThresholds else { return viewModel.powerSensors }
        return viewModel.powerSensors.sorted { a, b in
            severityRank(a.alertStatus(thresholds: t)) > severityRank(b.alertStatus(thresholds: t))
        }
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
                            Text("Riordina")
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
