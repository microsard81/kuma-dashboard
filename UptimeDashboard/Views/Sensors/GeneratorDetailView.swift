// Feature: native-apps-sensor-integration

import SwiftUI

/// Detail view showing all Generator sensors with sparklines.
/// Swipe right on a sensor to enter reorder mode (drag & drop).
/// Order is persisted in UserDefaults.
struct GeneratorDetailView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var isReordering = false
    @State private var manualOrder: [SensorReading] = []

    private let orderKey = "sensor_order_generator"

    private var displaySensors: [SensorReading] {
        if isReordering { return manualOrder }

        let saved = loadSavedOrder()
        var baseOrder: [SensorReading]
        let hasCustomOrder: Bool
        if !saved.isEmpty {
            var ordered: [SensorReading] = []
            let sensorMap = Dictionary(uniqueKeysWithValues: viewModel.generatorSensors.map { ($0.id, $0) })
            for id in saved {
                if let s = sensorMap[id] { ordered.append(s) }
            }
            for s in viewModel.generatorSensors where !saved.contains(s.id) {
                ordered.append(s)
            }
            baseOrder = ordered
            hasCustomOrder = true
        } else {
            baseOrder = viewModel.generatorSensors
            hasCustomOrder = false
        }

        if hasCustomOrder {
            let critical = baseOrder.filter { $0.status == .critical }
            let normal = baseOrder.filter { $0.status == .normal }
            return critical + normal
        }

        // Nessun ordine manuale: applica sortOrder globale
        let sortOrder = UserDefaults.standard.string(forKey: "sortOrder") ?? "severity"
        if sortOrder == "alphabetical" {
            return baseOrder.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        // Per gravità: ordina alfabeticamente dentro ogni gruppo
        let critical = baseOrder.filter { $0.status == .critical }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let normal = baseOrder.filter { $0.status == .normal }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return critical + normal
    }

    var body: some View {
        List {
            if isReordering {
                ForEach(manualOrder) { sensor in
                    sensorRow(sensor)
                }
                .onMove { from, to in
                    manualOrder.move(fromOffsets: from, toOffset: to)
                }
            } else {
                ForEach(displaySensors) { sensor in
                    sensorRow(sensor)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                startReorder()
                            } label: {
                                Label("Riordina", systemImage: "arrow.up.arrow.down")
                            }
                            .tint(.blue)
                        }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, isReordering ? .constant(.active) : .constant(.inactive))
        .navigationTitle("Generatori")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isReordering {
                Button("Fine") {
                    saveOrder()
                    withAnimation { isReordering = false }
                }
            }
        }
        .refreshable { await viewModel.refresh() }
    }

    private func sensorRow(_ sensor: SensorReading) -> some View {
        SensorCardView(
            sensor: sensor,
            historyPoints: viewModel.sensorHistory[sensor.id] ?? []
        )
    }

    private func startReorder() {
        manualOrder = displaySensors
        withAnimation { isReordering = true }
    }

    private func saveOrder() {
        let ids = manualOrder.map { $0.id }
        UserDefaults.standard.set(ids, forKey: orderKey)
    }

    private func loadSavedOrder() -> [String] {
        UserDefaults.standard.stringArray(forKey: orderKey) ?? []
    }
}
