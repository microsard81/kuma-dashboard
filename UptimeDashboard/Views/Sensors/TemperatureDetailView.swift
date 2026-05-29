// Feature: native-apps-sensor-integration

import SwiftUI

/// Detail view showing all temperature sensors with sparklines.
/// Swipe right on a sensor to enter reorder mode (drag & drop).
/// Order is persisted in UserDefaults.
struct TemperatureDetailView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var isReordering = false
    @State private var manualOrder: [SensorReading] = []
    @State private var isCriticalCollapsed = false
    @State private var isWarningCollapsed = false
    @State private var isNormalCollapsed = false

    private let orderKey = "sensor_order_temperature"

    private var displaySensors: [SensorReading] {
        if isReordering { return manualOrder }

        // Base order: saved custom order or default
        let saved = loadSavedOrder()
        var baseOrder: [SensorReading]
        if !saved.isEmpty {
            var ordered: [SensorReading] = []
            let sensorMap = Dictionary(uniqueKeysWithValues: viewModel.temperatureSensors.map { ($0.id, $0) })
            for id in saved {
                if let s = sensorMap[id] { ordered.append(s) }
            }
            for s in viewModel.temperatureSensors where !saved.contains(s.id) {
                ordered.append(s)
            }
            baseOrder = ordered
        } else {
            baseOrder = viewModel.temperatureSensors
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
            if isReordering {
                ForEach(manualOrder) { sensor in
                    SensorCardView(sensor: sensor, thresholds: viewModel.sensorThresholds, historyPoints: viewModel.sensorHistory[sensor.id] ?? [])
                        .listRowSeparator(.visible)
                }
                .onMove { from, to in manualOrder.move(fromOffsets: from, toOffset: to) }
            } else {
                let criticalSensors = displaySensors.filter { viewModel.sensorThresholds != nil && $0.alertStatus(thresholds: viewModel.sensorThresholds!) == .critical }
                let warningSensors = displaySensors.filter { viewModel.sensorThresholds != nil && $0.alertStatus(thresholds: viewModel.sensorThresholds!) == .warning }
                let normalSensors = displaySensors.filter { viewModel.sensorThresholds == nil || $0.alertStatus(thresholds: viewModel.sensorThresholds!) == .normal }
                let allNormal = criticalSensors.isEmpty && warningSensors.isEmpty

                if !criticalSensors.isEmpty {
                    Section(isExpanded: Binding(get: { !isCriticalCollapsed }, set: { isCriticalCollapsed = !$0 })) {
                        ForEach(criticalSensors) { sensor in
                            sensorRow(sensor)
                        }
                    } header: {
                        Label("Critical (\(criticalSensors.count))", systemImage: "exclamationmark.octagon.fill")
                            .foregroundColor(.red)
                    }
                }

                if !warningSensors.isEmpty {
                    Section(isExpanded: Binding(get: { !isWarningCollapsed }, set: { isWarningCollapsed = !$0 })) {
                        ForEach(warningSensors) { sensor in
                            sensorRow(sensor)
                        }
                    } header: {
                        Label("Warning (\(warningSensors.count))", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                    }
                }

                if !normalSensors.isEmpty {
                    if allNormal {
                        ForEach(normalSensors) { sensor in
                            sensorRow(sensor)
                        }
                    } else {
                        Section(isExpanded: Binding(get: { !isNormalCollapsed }, set: { isNormalCollapsed = !$0 })) {
                            ForEach(normalSensors) { sensor in
                                sensorRow(sensor)
                            }
                        } header: {
                            Label("Normale (\(normalSensors.count))", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
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

    @ViewBuilder
    private func sensorRow(_ sensor: SensorReading) -> some View {
        SensorCardView(sensor: sensor, thresholds: viewModel.sensorThresholds, historyPoints: viewModel.sensorHistory[sensor.id] ?? [])
            .listRowSeparator(.visible)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if !isReordering {
                    Button {
                        manualOrder = displaySensors
                        withAnimation { isReordering = true }
                    } label: {
                        Label("Riordina", systemImage: "arrow.up.arrow.down")
                    }
                    .tint(.orange)
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
