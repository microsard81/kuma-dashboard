// Feature: native-apps-sensor-integration

import SwiftUI
import UserNotifications

/// View showing notification history (last 30 days).
/// Unread notifications appear at the top with blue background.
/// Swipe left to mark as read.
struct NotificationHistoryView: View {
    @State private var notifications: [NotificationRecord] = []

    private var unreadNotifications: [NotificationRecord] {
        notifications.filter { !$0.isRead }
    }

    private var readNotifications: [NotificationRecord] {
        notifications.filter { $0.isRead }
    }

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
                    // Unread first
                    if !unreadNotifications.isEmpty {
                        Section {
                            ForEach(unreadNotifications) { notif in
                                NotificationRow(notification: notif)
                                    .listRowBackground(Color.blue.opacity(0.08))
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            markAsRead(notif)
                                        } label: {
                                            Label("Letta", systemImage: "envelope.open")
                                        }
                                        .tint(.blue)
                                    }
                            }
                        } header: {
                            Text("Non lette (\(unreadNotifications.count))")
                        }
                    }

                    // Read
                    if !readNotifications.isEmpty {
                        Section {
                            ForEach(readNotifications) { notif in
                                NotificationRow(notification: notif)
                            }
                        } header: {
                            if !unreadNotifications.isEmpty {
                                Text("Lette")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    NotificationStore.shared.markAllAsRead()
                    withAnimation { notifications = NotificationStore.shared.loadAll() }
                }
            }
        }
        .navigationTitle("Notifiche")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !unreadNotifications.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Segna tutte come lette") {
                        NotificationStore.shared.markAllAsRead()
                        withAnimation { notifications = NotificationStore.shared.loadAll() }
                    }
                    .font(.caption)
                }
            }
        }
        .onAppear { loadNotifications() }
    }

    private func loadNotifications() {
        notifications = NotificationStore.shared.loadAll()
    }

    private func markAsRead(_ notif: NotificationRecord) {
        NotificationStore.shared.markAsRead(id: notif.id)
        withAnimation { notifications = NotificationStore.shared.loadAll() }
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

struct NotificationRecord: Identifiable, Codable {
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

    private init() {}

    /// Number of unread notifications.
    var unreadCount: Int {
        loadAll().filter { !$0.isRead }.count
    }

    /// Mark all notifications as read.
    func markAllAsRead() {
        var records = loadAll()
        for i in records.indices { records[i].isRead = true }
        persist(records)
    }

    /// Mark a single notification as read.
    func markAsRead(id: UUID) {
        var records = loadAll()
        if let idx = records.firstIndex(where: { $0.id == id }) {
            records[idx].isRead = true
            persist(records)
        }
    }

    /// Save a new notification only if not a duplicate (same requestId).
    func saveIfNotDuplicate(title: String, body: String, requestId: String? = nil) {
        if let rid = requestId {
            let existing = loadAll()
            if existing.contains(where: { $0.requestId == rid }) { return }
        }
        save(title: title, body: body, requestId: requestId)
    }

    /// Save a new notification to history.
    func save(title: String, body: String, requestId: String? = nil) {
        var records = loadAll()
        // Dedup by requestId
        if let rid = requestId, records.contains(where: { $0.requestId == rid }) { return }
        records.insert(NotificationRecord(title: title, body: body, requestId: requestId), at: 0)
        let cutoff = Date().addingTimeInterval(-maxAge)
        records = records.filter { $0.date > cutoff }
        persist(records)
    }

    /// Load all notifications (newest first), pruning old ones.
    func loadAll() -> [NotificationRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              var records = try? JSONDecoder().decode([NotificationRecord].self, from: data) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-maxAge)
        records = records.filter { $0.date > cutoff }
        return records.sorted { $0.date > $1.date }
    }

    private func persist(_ records: [NotificationRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
