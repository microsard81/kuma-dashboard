import Foundation

// MARK: - MacPinnedItem

struct MacPinnedItem: Identifiable, Codable, Equatable {
    let id: String
    let type: PinnedType

    enum PinnedType: String, Codable {
        case portale
        case temperatura
        case potenza
        case ups
        case generatore
    }
}

// MARK: - MacPinnedStore

final class MacPinnedStore {
    static let shared = MacPinnedStore()
    private let key = "mac_pinned_items"

    private init() {}

    func loadAll() -> [MacPinnedItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([MacPinnedItem].self, from: data) else {
            return []
        }
        return items
    }

    func isPinned(id: String) -> Bool {
        loadAll().contains { $0.id == id }
    }

    func pin(id: String, type: MacPinnedItem.PinnedType) {
        var items = loadAll()
        guard !items.contains(where: { $0.id == id }) else { return }
        items.append(MacPinnedItem(id: id, type: type))
        persist(items)
    }

    func unpin(id: String) {
        var items = loadAll()
        items.removeAll { $0.id == id }
        persist(items)
    }

    func reorder(_ items: [MacPinnedItem]) {
        persist(items)
    }

    private func persist(_ items: [MacPinnedItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
