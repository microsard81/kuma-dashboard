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
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Header "Non lette"
                        if notifications.contains(where: { !$0.isRead }) {
                            HStack {
                                Text("Non lette (\(notifications.filter { !$0.isRead }.count))")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        }

                        ForEach(notifications.filter { !$0.isRead }) { notif in
                            NotificationSwipeRow(
                                notification: notif,
                                isUnread: true,
                                onAction: { markAsRead(notif) }
                            )
                            .id(notif.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                        }

                        // Header "Lette"
                        if notifications.contains(where: { $0.isRead }) {
                            HStack {
                                Text("Lette")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                        }

                        ForEach(notifications.filter { $0.isRead }) { notif in
                            NotificationSwipeRow(
                                notification: notif,
                                isUnread: false,
                                onAction: { markAsUnread(notif) }
                            )
                            .id(notif.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                        }
                    }
                    .padding(.bottom, 16)
                }
                .refreshable {
                    NotificationStore.shared.markAllAsRead()
                    withAnimation(.easeInOut(duration: 0.35)) {
                        reloadNotifications()
                    }
                }
            }
        }
        .navigationTitle("Notifiche")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadNotifications() }
    }

    private func loadNotifications() {
        reloadNotifications()
        #if DEBUG
        // Seed 4 test notifications if empty (con orari diversi)
        if notifications.isEmpty {
            seedDebugNotifications()
            reloadNotifications()
        }
        #endif
    }

    #if DEBUG
    private func seedDebugNotifications() {
        let now = Date()
        let records: [(String, String, TimeInterval, Bool)] = [
            ("⚠️ Temperatura critica", "DCUR - Temperatura ha superato la soglia critica (47.2°C)", -120, false),
            ("⛔ Portale DOWN", "www.regione.vda.it non raggiungibile da tutte le sonde", -300, false),
            ("⚡ Potenza bassa", "INV2 - Alimentazione sotto soglia warning (4.1 kW)", -1800, true),
            ("✅ Ripristino servizio", "mail.cst.inva.it è tornato UP su tutte le sonde", -3600, true),
        ]
        // Salva direttamente con date custom
        for (title, body, offset, isRead) in records {
            var record = NotificationRecord(title: title, body: body, date: now.addingTimeInterval(offset), isRead: isRead)
            _ = record // suppress warning
            // Usa il metodo interno per salvare con data custom
            var all = NotificationStore.shared.loadAll()
            all.insert(NotificationRecord(title: title, body: body, date: now.addingTimeInterval(offset), isRead: isRead), at: 0)
            if let data = try? JSONEncoder().encode(all) {
                UserDefaults.standard.set(data, forKey: "notification_history")
            }
        }
    }
    #endif

    private func markAsRead(_ notif: NotificationRecord) {
        NotificationStore.shared.markAsRead(id: notif.id)
        withAnimation(.easeInOut(duration: 0.35)) {
            if let idx = notifications.firstIndex(where: { $0.id == notif.id }) {
                notifications[idx].isRead = true
            }
        }
    }

    private func markAsUnread(_ notif: NotificationRecord) {
        NotificationStore.shared.markAsUnread(id: notif.id)
        withAnimation(.easeInOut(duration: 0.35)) {
            if let idx = notifications.firstIndex(where: { $0.id == notif.id }) {
                notifications[idx].isRead = false
            }
        }
    }

    private func reloadNotifications() {
        let all = NotificationStore.shared.loadAll()
        notifications = all.sorted {
            if $0.isRead != $1.isRead { return !$0.isRead }
            return $0.date > $1.date
        }
    }
}

// MARK: - NotificationSwipeRow (custom swipe senza List)

private struct NotificationSwipeRow: View {
    let notification: NotificationRecord
    let isUnread: Bool
    let onAction: () -> Void

    @State private var offset: CGFloat = 0

    private let actionWidth: CGFloat = 80

    var body: some View {
        ZStack(alignment: .trailing) {
            // Action button (revealed on swipe)
            HStack {
                Spacer()
                Button {
                    // Chiudi lo swipe prima di eseguire l'azione
                    withAnimation(.easeOut(duration: 0.15)) { offset = 0 }
                    // Esegui l'azione dopo la chiusura dello swipe
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onAction()
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: isUnread ? "envelope.open" : "envelope.badge")
                            .font(.system(size: 16))
                        Text(isUnread ? "Letta" : "Non letta")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.white)
                    .frame(width: actionWidth, maxHeight: .infinity)
                }
                .frame(width: actionWidth)
                .background(Color.blue)
            }

            // Main content
            NotificationRow(notification: notification)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isUnread ? Color.blue.opacity(0.08) : Color(.systemBackground))
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            if value.translation.width < 0 {
                                offset = max(value.translation.width, -actionWidth)
                            } else if offset < 0 {
                                // Permetti di chiudere trascinando a destra
                                offset = min(0, offset + value.translation.width)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.easeOut(duration: 0.2)) {
                                if value.translation.width < -actionWidth / 2 {
                                    offset = -actionWidth
                                } else {
                                    offset = 0
                                }
                            }
                        }
                )
        }
        .frame(maxWidth: .infinity)
        .clipped()
        // Reset offset quando l'elemento cambia stato (viene riusato)
        .onChange(of: notification.isRead) { _ in
            offset = 0
        }

        Divider()
            .padding(.leading, 16)
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
