// Feature: native-apps-sensor-integration

import SwiftUI

/// Detail view showing all uptime monitors with sparklines and probe indicators.
/// Swipe right on a monitor to enter reorder mode. Order is persisted.
struct PortalsDetailView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @State private var isReordering = false
    @State private var manualOrder: [MonitorItem] = []

    private let orderKey = "monitor_order_portals"

    private var displayItems: [MonitorItem] {
        if isReordering { return manualOrder }
        let saved = loadSavedOrder()
        if !saved.isEmpty {
            var ordered: [MonitorItem] = []
            let itemMap = Dictionary(uniqueKeysWithValues: viewModel.filteredItems.map { ($0.id.uuidString, $0) })
            for id in saved {
                if let item = itemMap[id] { ordered.append(item) }
            }
            for item in viewModel.filteredItems where !saved.contains(item.id.uuidString) {
                ordered.append(item)
            }
            return ordered
        }
        return viewModel.filteredItems
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if isReordering {
                    // Flat list for reordering
                    ForEach(manualOrder) { item in
                        MonitorRowView(item: item, openURL: openURL)
                            .listRowBackground(rowBackground(for: item.rowColor))
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                // No swipe in reorder mode
                            }
                    }
                    .onMove { from, to in
                        manualOrder.move(fromOffsets: from, toOffset: to)
                    }
                } else {
                    // Normal grouped view
                    let downItems = displayItems.filter { $0.rowColor == .red }
                    let mismatchItems = displayItems.filter { $0.rowColor == .yellow }
                    let upItems = displayItems.filter { $0.rowColor == .green }
                    let allUp = downItems.isEmpty && mismatchItems.isEmpty

                    if !downItems.isEmpty {
                        Section {
                            ForEach(downItems) { item in
                                monitorRow(item)
                            }
                        } header: {
                            Label("DOWN", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(DeviceAdaptive.sectionHeaderFont)
                        }
                    }

                    if !mismatchItems.isEmpty {
                        Section {
                            ForEach(mismatchItems) { item in
                                monitorRow(item)
                            }
                        } header: {
                            Label("Mismatch", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(DeviceAdaptive.sectionHeaderFont)
                        }
                    }

                    if !upItems.isEmpty {
                        if allUp {
                            ForEach(upItems) { item in
                                monitorRow(item)
                            }
                        } else {
                            Section {
                                ForEach(upItems) { item in
                                    monitorRow(item)
                                }
                            } header: {
                                Label("UP", systemImage: "checkmark.circle.fill")
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
        .navigationTitle("Portali")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isReordering {
                    Button("Termina") {
                        saveOrder(manualOrder.map(\.id.uuidString))
                        withAnimation { isReordering = false }
                    }
                    .bold()
                } else if viewModel.downCount > 0 {
                    Toggle(isOn: $viewModel.isOnlyDownFilter) {
                        Label("Solo DOWN", systemImage: viewModel.isOnlyDownFilter
                              ? "exclamationmark.triangle.fill"
                              : "exclamationmark.triangle")
                    }
                    .toggleStyle(.button)
                    .tint(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func monitorRow(_ item: MonitorItem) -> some View {
        MonitorRowView(item: item, openURL: openURL)
            .listRowBackground(rowBackground(for: item.rowColor))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    manualOrder = displayItems
                    withAnimation { isReordering = true }
                } label: {
                    Text("Riordina")
                }
                .tint(.green)
            }
    }

    private func rowBackground(for color: RowColor) -> Color {
        switch color {
        case .red:    return Color.red.opacity(0.12)
        case .yellow: return Color.yellow.opacity(0.10)
        case .green:  return Color.clear
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
