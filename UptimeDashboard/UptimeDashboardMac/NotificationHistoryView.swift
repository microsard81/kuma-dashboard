// Feature: native-apps-sensor-integration

import SwiftUI
import UserNotifications

/// View showing notification history (last 30 days).
/// Notifications are stored locally in UserDefaults when received.
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
                    ForEach(notifications) { notif in
                        NotificationRow(notification: notif)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Notifiche")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { loadNotifications() }
    }

    private func loadNotifications() {
        notifications = NotificationStore.shared.loadAll()
    }
}

// MARK: - NotificationRow

private struct NotificationRow: View {
    let notification: NotificationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
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

    init(title: String, body: String, date: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.date = date
    }
}

// MARK: - NotificationStore

final class NotificationStore {
    static let shared = NotificationStore()
    private let key = "notification_history"
    private let lastReadKey = "notification_last_read_date"
    private let maxAge: TimeInterval = 30 * 24 * 3600 // 30 days

    private init() {}

    /// Number of unread notifications (received after last read date).
    var unreadCount: Int {
        let lastRead = UserDefaults.standard.object(forKey: lastReadKey) as? Date ?? Date.distantPast
        return loadAll().filter { $0.date > lastRead }.count
    }

    /// Mark all notifications as read.
    func markAllAsRead() {
        UserDefaults.standard.set(Date(), forKey: lastReadKey)
    }

    /// Save a new notification to history.
    func save(title: String, body: String) {
        var records = loadAll()
        records.insert(NotificationRecord(title: title, body: body), at: 0)
        // Prune older than 30 days
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
