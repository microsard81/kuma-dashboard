// Feature: native-apps-sensor-integration

import SwiftUI

// MARK: - PinnedItem Model

struct PinnedItem: Identifiable, Codable, Equatable {
    let id: String          // monitor name or sensor id
    let type: PinnedType    // portale, temperatura, potenza

    enum PinnedType: String, Codable {
        case portale
        case temperatura
        case potenza
        case ups
        case generatore
    }
}

// MARK: - PinnedStore

final class PinnedStore {
    static let shared = PinnedStore()
    private let key = "pinned_items"

    private init() {}

    func loadAll() -> [PinnedItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([PinnedItem].self, from: data) else {
            return []
        }
        return items
    }

    func isPinned(id: String) -> Bool {
        loadAll().contains { $0.id == id }
    }

    func pin(id: String, type: PinnedItem.PinnedType) {
        var items = loadAll()
        guard !items.contains(where: { $0.id == id }) else { return }
        items.append(PinnedItem(id: id, type: type))
        persist(items)
        NotificationCenter.default.post(name: .pinnedItemsChanged, object: nil)
    }

    func unpin(id: String) {
        var items = loadAll()
        items.removeAll { $0.id == id }
        persist(items)
        NotificationCenter.default.post(name: .pinnedItemsChanged, object: nil)
    }

    func unpinAll() {
        persist([])
        NotificationCenter.default.post(name: .pinnedItemsChanged, object: nil)
    }

    func reorder(_ items: [PinnedItem]) {
        persist(items)
    }

    private func persist(_ items: [PinnedItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - PinnedCardView (compact card for home screen)

struct PinnedCardView: View {
    let item: PinnedItem
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 6) {
            // Icon
            Image(systemName: iconName)
                .font(.system(size: 18))
                .foregroundColor(textColor)

            // Name
            Text(displayName)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)

            // Status
            Text(statusText)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(textColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background(backgroundColor)
        .cornerRadius(10)
    }

    private var isAlert: Bool {
        switch item.type {
        case .portale:
            if let monitor = viewModel.items.first(where: { $0.name == item.id }) {
                return monitor.rowColor == .red || monitor.rowColor == .yellow
            }
        case .temperatura, .potenza, .ups, .generatore:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                return sensor.status == .critical
            }
        }
        return false
    }

    private var backgroundColor: Color {
        switch item.type {
        case .portale:
            if let monitor = viewModel.items.first(where: { $0.name == item.id }) {
                if monitor.rowColor == .red { return Color.red.opacity(0.85) }
                if monitor.rowColor == .yellow { return Color.yellow.opacity(0.75) }
            }
            return Color(.systemGray6)
        case .temperatura:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                if sensor.status == .critical { return Color.red.opacity(0.85) }
            }
            return Color(.systemGray6)
        case .potenza:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                if sensor.status == .critical { return Color.red.opacity(0.85) }
            }
            return Color(.systemGray6)
        case .ups, .generatore:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                if sensor.status == .critical { return Color.red.opacity(0.85) }
            }
            return Color(.systemGray6)
        }
    }

    private var textColor: Color {
        if isAlert { return .white }
        return cardColor
    }

    private var displayName: String {
        item.id.replacingOccurrences(of: "INVA - ", with: "")
    }

    private var iconName: String {
        switch item.type {
        case .portale: return "globe"
        case .temperatura: return "thermometer.medium"
        case .potenza: return "bolt.fill"
        case .ups: return "battery.75percent"
        case .generatore: return "fuelpump.fill"
        }
    }

    private var cardColor: Color {
        switch item.type {
        case .portale:
            if let monitor = viewModel.items.first(where: { $0.name == item.id }) {
                if monitor.rowColor == .red { return .red }
                if monitor.rowColor == .yellow { return .yellow }
            }
            return .green
        case .temperatura:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                if sensor.status == .critical { return .red }
            }
            return .orange
        case .potenza:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                if sensor.status == .critical { return .red }
            }
            return .blue
        case .ups:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                if sensor.status == .critical { return .red }
            }
            return .purple
        case .generatore:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                if sensor.status == .critical { return .red }
            }
            return .orange
        }
    }

    private var statusText: String {
        switch item.type {
        case .portale:
            if let monitor = viewModel.items.first(where: { $0.name == item.id }) {
                return monitor.final.rawValue
            }
            return "—"
        case .temperatura, .potenza, .ups, .generatore:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                return sensor.displayValueWithUnit
            }
            return "—"
        }
    }
}


// MARK: - Notification Name

extension Notification.Name {
    static let pinnedItemsChanged = Notification.Name("pinnedItemsChanged")
}




// MARK: - Drop Delegate for grid reorder

struct PinnedReorderDropDelegate: DropDelegate {
    let item: PinnedItem
    @Binding var items: [PinnedItem]
    @Binding var draggingItem: PinnedItem?

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingItem,
              dragging.id != item.id,
              let fromIndex = items.firstIndex(where: { $0.id == dragging.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.default) {
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        PinnedStore.shared.reorder(items)
        return true
    }
}
