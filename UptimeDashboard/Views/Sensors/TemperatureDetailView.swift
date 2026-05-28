// Feature: native-apps-sensor-integration

import SwiftUI

/// Detail view showing all temperature sensors with sparklines.
/// Swipe right on a sensor to enter reorder mode (drag & drop).
/// Order is persisted in UserDefaults.
struct TemperatureDetailView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var isReordering = false
    @State private var manualOrder: [SensorReading] = []

    private let orderKey = "sensor_order_temperature"

    private var displaySensors: [SensorReading] {
        if isReordering { return manualOrder }
        let saved = loadSavedOrder()
        if !saved.isEmpty {
            // Reorder based on saved IDs, append any new sensors at the end
            var ordered: [SensorReading] = []
            let sensorMap = Dictionary(uniqueKeysWithValues: viewModel.temperatureSensors.map { ($0.id, $0) })
            for id in saved {
                if let s = sensorMap[id] { ordered.append(s) }
            }
            // Append sensors not in saved order
            for s in viewModel.temperatureSensors where !saved.contains(s.id) {
                ordered.append(s)
            }
            return ordered
        }
        // Default: sort by severity
        guard let t = viewModel.sensorThresholds else { return viewModel.temperatureSensors }
        return viewModel.temperatureSensors.sorted { a, b in
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
                        .tint(.orange)
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
        .navigationTitle("Temperatura (°C)")
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
