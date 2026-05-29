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
    @State private var showPinConfirmation = false
    @State private var showUnpinConfirmation = false
    @State private var pinnedIds: Set<String> = Set(PinnedStore.shared.loadAll().map(\.id))

    private let orderKey = "sensor_order_temperature"

    private var displaySensors: [SensorReading] {
        if isReordering { return manualOrder }

        // Base order: saved custom order or default
        let saved = loadSavedOrder()
        var baseOrder: [SensorReading]
        let hasCustomOrder: Bool
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
            hasCustomOrder = true
        } else {
            baseOrder = viewModel.temperatureSensors
            hasCustomOrder = false
        }

        // Se c'è ordine manuale, rispettalo (solo gravità in cima)
        guard let t = viewModel.sensorThresholds else { return baseOrder }
        if hasCustomOrder {
            // Ordine manuale: solo critical/warning in cima, il resto nell'ordine salvato
            let critical = baseOrder.filter { $0.alertStatus(thresholds: t) == .critical }
            let warning = baseOrder.filter { $0.alertStatus(thresholds: t) == .warning }
            let normal = baseOrder.filter { $0.alertStatus(thresholds: t) == .normal }
            return critical + warning + normal
        }

        // Nessun ordine manuale: applica sortOrder globale
        let sortOrder = UserDefaults.standard.string(forKey: "sortOrder") ?? "severity"
        if sortOrder == "alphabetical" {
            return baseOrder.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        // Per gravità: ordina alfabeticamente dentro ogni gruppo
        let critical = baseOrder.filter { $0.alertStatus(thresholds: t) == .critical }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let warning = baseOrder.filter { $0.alertStatus(thresholds: t) == .warning }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let normal = baseOrder.filter { $0.alertStatus(thresholds: t) == .normal }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
        .listStyle(.plain)
        .environment(\.editMode, isReordering ? .constant(.active) : .constant(.inactive))
        .refreshable { await viewModel.refresh() }
        .navigationTitle("Temperatura (°C)")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { CheckmarkPopup(isPresented: $showPinConfirmation) }
        .overlay { CheckmarkPopup(isPresented: $showUnpinConfirmation, isRemoval: true) }
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
            .swipeActions(edge: .trailing) {
                if pinnedIds.contains(sensor.id) {
                    Button {
                        PinnedStore.shared.unpin(id: sensor.id)
                        pinnedIds.remove(sensor.id)
                        withAnimation { showUnpinConfirmation = true }
                    } label: {
                        Label("Rimuovi", systemImage: "minus.circle")
                    }
                    .tint(.red)
                } else {
                    Button {
                        PinnedStore.shared.pin(id: sensor.id, type: .temperatura)
                        pinnedIds.insert(sensor.id)
                        withAnimation { showPinConfirmation = true }
                    } label: {
                        Label("Home", systemImage: "plus.circle")
                    }
                    .tint(.purple)
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
