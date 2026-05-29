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

    private func persist(_ items: [PinnedItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - PinnedCardView (compact card for home screen)

struct PinnedCardView: View {
    let item: PinnedItem
    let viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .font(.system(size: 16))
                    .foregroundColor(cardColor)
            }

            // Name
            Text(displayName)
                .font(.caption.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Status
            Text(statusText)
                .font(.caption2.bold())
                .foregroundColor(cardColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private var displayName: String {
        item.id.replacingOccurrences(of: "INVA - ", with: "")
    }

    private var iconName: String {
        switch item.type {
        case .portale: return "globe"
        case .temperatura: return "thermometer.medium"
        case .potenza: return "bolt.fill"
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
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }),
               let t = viewModel.sensorThresholds {
                let status = sensor.alertStatus(thresholds: t)
                if status == .critical { return .red }
                if status == .warning { return .yellow }
            }
            return .orange
        case .potenza:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }),
               let t = viewModel.sensorThresholds {
                let status = sensor.alertStatus(thresholds: t)
                if status == .critical { return .red }
                if status == .warning { return .yellow }
            }
            return .blue
        }
    }

    private var statusText: String {
        switch item.type {
        case .portale:
            if let monitor = viewModel.items.first(where: { $0.name == item.id }) {
                return monitor.final.rawValue
            }
            return "—"
        case .temperatura, .potenza:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                return String(format: "%.1f", sensor.value)
            }
            return "—"
        }
    }
}


// MARK: - Notification Name

extension Notification.Name {
    static let pinnedItemsChanged = Notification.Name("pinnedItemsChanged")
}
