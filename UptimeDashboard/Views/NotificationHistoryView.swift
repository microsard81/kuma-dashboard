// Feature: native-apps-sensor-integration

import SwiftUI
import UserNotifications

/// View showing notification history (last 30 days).
/// Unread notifications appear at the top with blue background.
/// Swipe left to mark as read.
struct NotificationHistoryView: View {
    @State private var notifications: [NotificationRecord] = []

    var body: some View {
        Group {
            if notifications.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bell.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Nessuna notifica")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Le notifiche ricevute appariranno qui")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($notifications) { $notif in
                        NotificationRow(notification: notif)
                            .listRowBackground(notif.isRead ? Color.clear : Color.blue.opacity(0.08))
                            .swipeActions(edge: .trailing) {
                                if notif.isRead {
                                    Button {
                                        markAsUnread(notif)
                                    } label: {
                                        Label("Non letta", systemImage: "envelope.badge")
                                    }
                                    .tint(.blue)
                                } else {
                                    Button {
                                        markAsRead(notif)
                                    } label: {
                                        Label("Letta", systemImage: "envelope.open")
                                    }
                                    .tint(.blue)
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    NotificationStore.shared.markAllAsRead()
                    notifications = NotificationStore.shared.loadAll()
                }
                .overlay(alignment: .top) {
                    if notifications.contains(where: { !$0.isRead }) {
                        Text("↓ Segna tutte come lette")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, -20)
                    }
                }
            }
        }
        .navigationTitle("Notifiche")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadNotifications() }
    }

    private func loadNotifications() {
        let all = NotificationStore.shared.loadAll()
        // Ordina: non lette prima, poi per data decrescente
        notifications = all.sorted {
            if $0.isRead != $1.isRead { return !$0.isRead }
            return $0.date > $1.date
        }
        #if DEBUG
        // Seed 4 test notifications if empty
        if notifications.isEmpty {
            NotificationStore.shared.save(title: "⚠️ Temperatura critica", body: "DCUR - Temperatura ha superato la soglia critica (47.2°C)")
            NotificationStore.shared.save(title: "🔴 Portale DOWN", body: "www.regione.vda.it non raggiungibile da tutte le sonde")
            NotificationStore.shared.save(title: "⚡ Potenza bassa", body: "INV2 - Alimentazione sotto soglia warning (4.1 kW)")
            NotificationStore.shared.save(title: "✅ Ripristino servizio", body: "mail.cst.inva.it è tornato UP su tutte le sonde")
            let seeded = NotificationStore.shared.loadAll()
            notifications = seeded.sorted {
                if $0.isRead != $1.isRead { return !$0.isRead }
                return $0.date > $1.date
            }
        }
        #endif
    }

    private func markAsRead(_ notif: NotificationRecord) {
        NotificationStore.shared.markAsRead(id: notif.id)
        if let idx = notifications.firstIndex(where: { $0.id == notif.id }) {
            withAnimation(.easeInOut(duration: 0.25)) {
                notifications[idx].isRead = true
            }
        }
    }

    private func markAsUnread(_ notif: NotificationRecord) {
        NotificationStore.shared.markAsUnread(id: notif.id)
        if let idx = notifications.firstIndex(where: { $0.id == notif.id }) {
            withAnimation(.easeInOut(duration: 0.25)) {
                notifications[idx].isRead = false
            }
        }
    }
}

// MARK: - NotificationRow

private struct NotificationRow: View {
    let notification: NotificationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !notification.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
                Text(notification.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(formatDate(notification.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if !notification.body.isEmpty {
                Text(notification.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Ieri' HH:mm"
        } else {
            formatter.dateFormat = "dd/MM HH:mm"
        }
        return formatter.string(from: date)
    }
}

// MARK: - NotificationRecord

struct NotificationRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let body: String
    let date: Date
    var isRead: Bool
    var requestId: String?

    init(title: String, body: String, date: Date = Date(), isRead: Bool = false, requestId: String? = nil) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.date = date
        self.isRead = isRead
        self.requestId = requestId
    }
}

// MARK: - NotificationStore

final class NotificationStore {
    static let shared = NotificationStore()
    private let key = "notification_history"
    private let maxAge: TimeInterval = 30 * 24 * 3600 // 30 days
    private let queue = DispatchQueue(label: "notificationStore", qos: .userInitiated)

    private init() {}

    /// Number of unread notifications.
    var unreadCount: Int {
        queue.sync { loadAllInternal().filter { !$0.isRead }.count }
    }

    /// Mark all notifications as read.
    func markAllAsRead() {
        queue.sync {
            var records = loadAllInternal()
            for i in records.indices { records[i].isRead = true }
            persistInternal(records)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .notificationReadStateChanged, object: nil)
        }
    }

    /// Mark a single notification as read.
    func markAsRead(id: UUID) {
        queue.sync {
            var records = loadAllInternal()
            if let idx = records.firstIndex(where: { $0.id == id }) {
                records[idx].isRead = true
                persistInternal(records)
            }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .notificationReadStateChanged, object: nil)
        }
    }

    /// Mark a single notification as unread.
    func markAsUnread(id: UUID) {
        queue.sync {
            var records = loadAllInternal()
            if let idx = records.firstIndex(where: { $0.id == id }) {
                records[idx].isRead = false
                persistInternal(records)
            }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .notificationReadStateChanged, object: nil)
        }
    }

    /// Save a new notification only if not a duplicate (same requestId).
    func saveIfNotDuplicate(title: String, body: String, requestId: String? = nil) {
        var didSave = false
        queue.sync {
            if let rid = requestId {
                let existing = loadAllInternal()
                if existing.contains(where: { $0.requestId == rid }) { return }
            }
            saveInternal(title: title, body: body, requestId: requestId)
            didSave = true
        }
        if didSave {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .notificationReadStateChanged, object: nil)
            }
        }
    }

    /// Save a new notification to history (always saves, no dedup).
    func save(title: String, body: String, requestId: String? = nil) {
        queue.sync {
            saveInternal(title: title, body: body, requestId: requestId)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .notificationReadStateChanged, object: nil)
        }
    }

    private func saveInternal(title: String, body: String, requestId: String?) {
        var records = loadAllInternal()
        records.insert(NotificationRecord(title: title, body: body, requestId: requestId), at: 0)
        let cutoff = Date().addingTimeInterval(-maxAge)
        records = records.filter { $0.date > cutoff }
        persistInternal(records)
    }

    /// Load all notifications (newest first), pruning old ones.
    func loadAll() -> [NotificationRecord] {
        queue.sync { loadAllInternal() }
    }

    private func loadAllInternal() -> [NotificationRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              var records = try? JSONDecoder().decode([NotificationRecord].self, from: data) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-maxAge)
        records = records.filter { $0.date > cutoff }
        return records.sorted { $0.date > $1.date }
    }

    private func persistInternal(_ records: [NotificationRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let notificationReadStateChanged = Notification.Name("notificationReadStateChanged")
}
