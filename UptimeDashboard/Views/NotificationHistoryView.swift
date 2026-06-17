// Feature: native-apps-sensor-integration

import SwiftUI
import UserNotifications

// MARK: - Server Event Models (per syncFromServer)

private struct SyncServerEvent: Codable, Identifiable {
    let id: String
    let ts: String
    let type: String
    let name: String
    let from: String
    let to: String
    let detail: String?
    let severity: Int

    // Campi legacy (presenti in eventi salvati prima del fix)
    let title_legacy: String?
    let body_legacy: String?

    enum CodingKeys: String, CodingKey {
        case id, ts, type, name, from, to, detail, severity
        case title_legacy = "title"
        case body_legacy = "body"
    }

    var date: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: ts) ?? Date.distantPast
    }

    /// Genera il titolo dalla struttura dell'evento.
    var title: String {
        if let legacy = title_legacy, !legacy.isEmpty { return legacy }
        // Il backend include già l'emoji nel campo name
        return name
    }

    /// Genera il body dalla struttura dell'evento.
    var body: String {
        if let legacy = body_legacy, !legacy.isEmpty { return legacy }
        return detail ?? ""
    }
}

private struct SyncEventsResponse: Codable {
    let events: [SyncServerEvent]
    let count: Int
}

/// View showing notification history (last 30 days).
/// Unread notifications appear at the top with blue background.
/// Swipe left to mark as read.
struct NotificationHistoryView: View {
    @State private var notifications: [NotificationRecord] = []

    // Read state for server events — persisted locally by event ID
    private let readStateKey = "ios_event_read_state"
    private var readStateDefaults: UserDefaults {
        UserDefaults(suiteName: "group.cloud.sundata.uptimeDashboard") ?? .standard
    }

    private func loadReadEventIds() -> Set<String> {
        Set(readStateDefaults.stringArray(forKey: readStateKey) ?? [])
    }

    private func saveReadEventIds(_ ids: Set<String>) {
        readStateDefaults.set(Array(ids), forKey: readStateKey)
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
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Hint pull-to-refresh (solo se ci sono non lette)
                        if notifications.contains(where: { !$0.isRead }) {
                            Text("↓ Scorri per segnare tutte come lette")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }

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

                        // Singolo ForEach — ordine: non lette prima, poi lette
                        ForEach($notifications) { $notif in
                            // Header "Lette" prima del primo elemento letto
                            if notif.isRead && isFirstRead(notif) {
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

                            NotificationSwipeRow(
                                notification: $notif,
                                onAction: {
                                    toggleReadState(notif)
                                }
                            )
                            .id(notif.id)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .refreshable {
                    // Fetch from server and mark all as read
                    await fetchServerEvents()
                    markAllServerEventsAsRead()
                }
            }
        }
        .navigationTitle("Notifiche")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Clear local push badge when viewing notifications
            NotificationStore.shared.markAllAsRead()
            NotificationCenter.default.post(name: .notificationReadStateChanged, object: nil)
            loadNotifications()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            Task { await fetchServerEvents() }
        }
    }

    private func loadNotifications() {
        // Fetch events directly from server (Redis events only)
        Task {
            await fetchServerEvents()
        }
    }

    private func fetchServerEvents() async {
        let url = AppConfig.baseURL.appendingPathComponent("api/events")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: "200")]

        guard let requestURL = components?.url else { return }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            let eventsResponse = try JSONDecoder().decode(SyncEventsResponse.self, from: data)

            // Load read state from local UserDefaults (event IDs already marked as read)
            let readIds = loadReadEventIds()

            let records: [NotificationRecord] = eventsResponse.events
                .filter { $0.type != "global" }
                .map { event in
                NotificationRecord(
                    title: event.title,
                    body: event.body,
                    date: event.date,
                    isRead: readIds.contains(event.id),
                    requestId: event.id
                )
            }

            await MainActor.run {
                notifications = records.sorted {
                    if $0.isRead != $1.isRead { return !$0.isRead }
                    return $0.date > $1.date
                }
            }
        } catch {
            // Fallback: show whatever is available locally
            reloadNotifications()
        }
    }

    private func markAsRead(_ notif: NotificationRecord) {
        toggleReadState(notif)
    }

    private func markAsUnread(_ notif: NotificationRecord) {
        toggleReadState(notif)
    }

    private func toggleReadState(_ notif: NotificationRecord) {
        guard let idx = notifications.firstIndex(where: { $0.id == notif.id }) else { return }
        let newState = !notifications[idx].isRead

        // Persist read state by event ID (requestId = server event UUID)
        if let eventId = notifications[idx].requestId {
            var readIds = loadReadEventIds()
            if newState {
                readIds.insert(eventId)
            } else {
                readIds.remove(eventId)
            }
            saveReadEventIds(readIds)
        }

        withAnimation(.easeInOut(duration: 0.35)) {
            notifications[idx].isRead = newState
            notifications.sort {
                if $0.isRead != $1.isRead { return !$0.isRead }
                return $0.date > $1.date
            }
        }
    }

    private func isFirstRead(_ notif: NotificationRecord) -> Bool {
        notifications.first(where: { $0.isRead })?.id == notif.id
    }

    private func markAllServerEventsAsRead() {
        var readIds = loadReadEventIds()
        for notif in notifications {
            if let eventId = notif.requestId {
                readIds.insert(eventId)
            }
        }
        saveReadEventIds(readIds)
        for idx in notifications.indices {
            notifications[idx].isRead = true
        }
        NotificationStore.shared.markAllAsRead()
        NotificationCenter.default.post(name: .notificationReadStateChanged, object: nil)
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
    @Binding var notification: NotificationRecord
    let onAction: () -> Void

    @State private var offset: CGFloat = 0

    private let actionWidth: CGFloat = 80
    private let fullSwipeThreshold: CGFloat = 200

    private var isUnread: Bool { !notification.isRead }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Action button — visibile solo quando lo swipe è attivo
            if offset < 0 {
                HStack {
                    Spacer()
                    VStack(spacing: 2) {
                        Image(systemName: isUnread ? "envelope.open" : "envelope.badge")
                            .font(.system(size: 16))
                        Text(isUnread ? "Letta" : "Non letta")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.white)
                    .frame(width: max(-offset, actionWidth))
                    .frame(maxHeight: .infinity)
                    .background(Color.blue)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) { offset = 0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onAction()
                        }
                    }
                }
            }

            // Main content
            HStack {
                if isUnread {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isUnread ? Color.blue.opacity(0.08) : Color(.systemBackground))
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width < 0 {
                            offset = value.translation.width
                        } else if offset < 0 {
                            offset = min(0, offset + value.translation.width)
                        }
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else {
                            withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
                            return
                        }
                        // Full swipe: esegui azione direttamente
                        if value.translation.width < -fullSwipeThreshold {
                            withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                onAction()
                            }
                        } else if value.translation.width < -actionWidth / 2 {
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset = -actionWidth
                            }
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset = 0
                            }
                        }
                    }
            )
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .onChange(of: notification.isRead) { _ in
            offset = 0
        }

        Divider()
            .padding(.leading, 16)
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
    private let appGroupId = "group.cloud.sundata.uptimeDashboard"

    /// Shared UserDefaults (App Group) — usato sia dall'app che dalla Notification Service Extension
    private var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? UserDefaults.standard
    }

    private init() {
        // Migrazione: se ci sono dati nel vecchio UserDefaults.standard, spostali nell'App Group
        migrateFromStandardIfNeeded()
    }

    /// Migra i dati dal vecchio UserDefaults.standard all'App Group (una tantum)
    private func migrateFromStandardIfNeeded() {
        let standard = UserDefaults.standard
        guard let oldData = standard.data(forKey: key) else { return }
        // Se l'App Group non ha ancora dati, copia quelli vecchi
        let groupDefaults = UserDefaults(suiteName: appGroupId) ?? standard
        if groupDefaults.data(forKey: key) == nil {
            groupDefaults.set(oldData, forKey: key)
            standard.removeObject(forKey: key)
        }
    }

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

    /// Sync from backend: merge server events with local NSE records.
    /// Server events are authoritative — local duplicates (by requestId match) are skipped.
    func syncFromServer(baseURL: URL, session: URLSession? = nil) async {
        let url = baseURL.appendingPathComponent("api/events")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: "200")]

        guard let requestURL = components?.url else { return }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"

        let urlSession = session ?? URLSession.shared

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            let eventsResponse = try JSONDecoder().decode(SyncEventsResponse.self, from: data)

            queue.sync {
                var records = loadAllInternal()
                let existingIds = Set(records.compactMap { $0.requestId })

                for event in eventsResponse.events {
                    // Skip if already present (matched by server event ID stored as requestId)
                    if existingIds.contains(event.id) { continue }

                    let record = NotificationRecord(
                        title: event.title,
                        body: event.body,
                        date: event.date,
                        isRead: false,
                        requestId: event.id
                    )
                    records.append(record)
                }

                // Sort and prune
                let cutoff = Date().addingTimeInterval(-maxAge)
                records = records.filter { $0.date > cutoff }
                records.sort { $0.date > $1.date }
                persistInternal(records)
            }
        } catch {
            // Silently fail — local data is still available
        }
    }

    private func loadAllInternal() -> [NotificationRecord] {
        guard let data = defaults.data(forKey: key),
              var records = try? JSONDecoder().decode([NotificationRecord].self, from: data) else {
            return []
        }
        let cutoff = Date().addingTimeInterval(-maxAge)
        records = records.filter { $0.date > cutoff }
        return records.sorted { $0.date > $1.date }
    }

    private func persistInternal(_ records: [NotificationRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let notificationReadStateChanged = Notification.Name("notificationReadStateChanged")
}
