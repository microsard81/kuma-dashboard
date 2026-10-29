// Feature: probe-health — Stato sonde Kuma (check NodePing)
// Struttura e peculiarità identiche a PortalsDetailView.

import SwiftUI

/// Detail view con lo stato delle sonde di monitoraggio Kuma.
/// Stessa logica dei Portali: riordino (swipe-left), pin/unpin (swipe-right) con
/// popup di conferma, sezioni collassabili per stato, ordine custom persistente,
/// highlight temporaneo su scrollTo, sparkline con storico dei sample.
struct ProbeHealthDetailView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var scrollToId: String? = nil
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @State private var isReordering = false
    @State private var manualOrder: [KumaProbe] = []
    @State private var isDownCollapsed = false
    @State private var isUpCollapsed = false
    @State private var showPinConfirmation = false
    @State private var showUnpinConfirmation = false
    @State private var pinnedIds: Set<String> = Set(PinnedStore.shared.loadAll().map(\.id))
    @State private var highlightedId: String? = nil

    private let orderKey = "probe_order_sonde"

    private var displayItems: [KumaProbe] {
        if isReordering { return manualOrder }

        // Base order: saved custom order or default from viewModel
        let saved = loadSavedOrder()
        var baseOrder: [KumaProbe]
        if !saved.isEmpty {
            var ordered: [KumaProbe] = []
            let itemMap = Dictionary(uniqueKeysWithValues: viewModel.kumaProbes.map { ($0.id, $0) })
            for id in saved {
                if let item = itemMap[id] { ordered.append(item) }
            }
            for item in viewModel.kumaProbes where !saved.contains(item.id) {
                ordered.append(item)
            }
            baseOrder = ordered
        } else {
            baseOrder = viewModel.kumaProbes
        }

        // Stable sort: non operative prima, poi operative — preservando l'ordine relativo
        let down = baseOrder.filter { !$0.isOperative }
        let up = baseOrder.filter { $0.isOperative }
        return down + up
    }

    var body: some View {
        ScrollViewReader { proxy in
        VStack(spacing: 0) {
            List {
                if isReordering {
                    // Flat list for reordering
                    ForEach(manualOrder) { item in
                        ProbeRowView(probe: item)
                            .listRowBackground(rowBackground(for: item.isOperative))
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                // No swipe in reorder mode
                            }
                    }
                    .onMove { from, to in
                        manualOrder.move(fromOffsets: from, toOffset: to)
                    }
                } else {
                    // Normal grouped view
                    let downItems = displayItems.filter { !$0.isOperative }
                    let upItems = displayItems.filter { $0.isOperative }
                    let allUp = downItems.isEmpty

                    if !downItems.isEmpty {
                        Section(isExpanded: Binding(get: { !isDownCollapsed }, set: { isDownCollapsed = !$0 })) {
                            ForEach(downItems) { item in
                                probeRow(item)
                            }
                        } header: {
                            Label("Non operative (\(downItems.count))", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(DeviceAdaptive.sectionHeaderFont)
                        }
                    }

                    if !upItems.isEmpty {
                        if allUp {
                            ForEach(upItems) { item in
                                probeRow(item)
                            }
                        } else {
                            Section(isExpanded: Binding(get: { !isUpCollapsed }, set: { isUpCollapsed = !$0 })) {
                                ForEach(upItems) { item in
                                    probeRow(item)
                                }
                            } header: {
                                Label("Operative (\(upItems.count))", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(DeviceAdaptive.sectionHeaderFont)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, isReordering ? .constant(.active) : .constant(.inactive))
            .refreshable { await viewModel.refresh() }
        }
        .navigationTitle("Stato Sonde")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { CheckmarkPopup(isPresented: $showPinConfirmation) }
        .overlay { CheckmarkPopup(isPresented: $showUnpinConfirmation, isRemoval: true) }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isReordering {
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
    private func probeRow(_ item: KumaProbe) -> some View {
        ProbeRowView(probe: item)
            .id(item.id)
            .listRowBackground(rowBackground(for: item.isOperative))
            .overlay(
                Color.blue.opacity(highlightedId == item.id ? 0.4 : 0)
                    .animation(.easeOut(duration: 3.0), value: highlightedId)
                    .allowsHitTesting(false)
            )
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    manualOrder = displayItems
                    withAnimation { isReordering = true }
                } label: {
                    Label("Riordina", systemImage: "arrow.up.arrow.down")
                }
                .tint(.green)
            }
            .swipeActions(edge: .trailing) {
                if pinnedIds.contains(item.id) {
                    Button {
                        PinnedStore.shared.unpin(id: item.id)
                        pinnedIds.remove(item.id)
                        withAnimation { showUnpinConfirmation = true }
                    } label: {
                        Label("Rimuovi", systemImage: "minus.circle")
                    }
                    .tint(.red)
                } else {
                    Button {
                        PinnedStore.shared.pin(id: item.id, type: .sonda)
                        pinnedIds.insert(item.id)
                        withAnimation { showPinConfirmation = true }
                    } label: {
                        Label("Home", systemImage: "plus.circle")
                    }
                    .tint(.purple)
                }
            }
    }

    private func rowBackground(for isOperative: Bool) -> Color {
        isOperative ? Color.clear : Color.red.opacity(0.12)
    }

    // MARK: - Persistence

    private func saveOrder(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: orderKey)
    }

    private func loadSavedOrder() -> [String] {
        UserDefaults.standard.stringArray(forKey: orderKey) ?? []
    }
}

// MARK: - ProbeRowView
/// Riga di una sonda, modellata su MonitorRowView: nome, badge stato, sparkline storica.

struct ProbeRowView: View {
    let probe: KumaProbe
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @State private var selectedSegment: SparklineSegment? = nil

    private var selectionLabel: String? {
        guard let seg = selectedSegment, let ts = seg.timestamp else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it-IT")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: ts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(probe.label).font(DeviceAdaptive.monitorNameFont)
                Spacer()
                if let label = selectionLabel {
                    Text(label)
                        .font(DeviceAdaptive.selectionLabelFont)
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
                Text(probe.isOperative ? "OK" : "KO")
                    .font(DeviceAdaptive.statusBadgeFont).foregroundColor(.white)
                    .padding(.horizontal, DeviceAdaptive.badgeHPadding)
                    .padding(.vertical, DeviceAdaptive.badgeVPadding)
                    .background(probe.isOperative ? Color.green : Color.red)
                    .clipShape(Capsule())
            }
            .animation(.easeInOut(duration: 0.12), value: selectedSegment?.id)

            SparklineView(history: probe.history, selectedSegment: $selectedSegment, hapticEnabled: settingsVM.hapticEnabled)
                .frame(height: DeviceAdaptive.sparklineHeight)
        }
        .padding(.vertical, DeviceAdaptive.rowVerticalPadding)
    }
}
