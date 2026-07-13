// Feature: native-apps-sensor-integration

import SwiftUI

/// Detail view showing all power sensors with sparklines.
/// Swipe right on a sensor to enter reorder mode (drag & drop).
/// Order is persisted in UserDefaults.
struct PowerDetailView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var scrollToId: String? = nil
    @State private var isReordering = false
    @State private var manualOrder: [SensorReading] = []
    @State private var isCriticalCollapsed = false
    @State private var isNormalCollapsed = false
    @State private var showPinConfirmation = false
    @State private var showUnpinConfirmation = false
    @State private var pinnedIds: Set<String> = Set(PinnedStore.shared.loadAll().map(\.id))
    @State private var highlightedId: String? = nil

    private let orderKey = "sensor_order_power"

    private var displaySensors: [SensorReading] {
        if isReordering { return manualOrder }

        // Base order: saved custom order or default
        let saved = loadSavedOrder()
        var baseOrder: [SensorReading]
        let hasCustomOrder: Bool
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
            hasCustomOrder = true
        } else {
            baseOrder = viewModel.powerSensors
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

    private func severityRank(_ status: AlertStatus) -> Int {
        switch status {
        case .critical: return 2
        case .normal: return 0
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            if isReordering {
                ForEach(manualOrder) { sensor in
                    SensorCardView(sensor: sensor, historyPoints: viewModel.sensorHistory[sensor.id] ?? [])
                        .listRowSeparator(.visible)
                }
                .onMove { from, to in manualOrder.move(fromOffsets: from, toOffset: to) }
            } else {
                let criticalSensors = displaySensors.filter { $0.status == .critical }
                let normalSensors = displaySensors.filter { $0.status == .normal }
                let allNormal = criticalSensors.isEmpty

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
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, isReordering ? .constant(.active) : .constant(.inactive))
        .refreshable { await viewModel.refresh() }
        .navigationTitle("Potenza (kW)")
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
        .onAppear {
            if let id = scrollToId {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                    highlightedId = id
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 3.0)) { highlightedId = nil }
                }
            }
        }
        } // end ScrollViewReader
    }

    @ViewBuilder
    private func sensorRow(_ sensor: SensorReading) -> some View {
        SensorCardView(sensor: sensor, historyPoints: viewModel.sensorHistory[sensor.id] ?? [])
            .id(sensor.id)
            .listRowSeparator(.visible)
            .overlay(
                Color.blue.opacity(highlightedId == sensor.id ? 0.2 : 0)
                    .animation(.easeOut(duration: 3.0), value: highlightedId)
                    .allowsHitTesting(false)
            )
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
                        PinnedStore.shared.pin(id: sensor.id, type: .potenza)
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
