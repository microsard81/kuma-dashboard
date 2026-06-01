// Notification Service Extension (iOS) — intercetta le push APNs prima che vengano mostrate.
// Salva ogni notifica nello shared UserDefaults (App Group) così l'app principale
// può mostrarle nello storico anche se era chiusa al momento della ricezione.

import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    private let appGroupId = "group.cloud.sundata.uptimeDashboard"

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        // Salva la notifica nello shared store
        let title = request.content.title
        let body = request.content.body
        let requestId = request.identifier

        saveNotification(title: title, body: body, requestId: requestId)

        // Passa il contenuto originale (non modificato)
        if let content = bestAttemptContent {
            contentHandler(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let content = bestAttemptContent {
            contentHandler(content)
        }
    }

    // MARK: - Shared Store

    private func saveNotification(title: String, body: String, requestId: String) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        let key = "notification_history"

        var records: [SharedNotificationRecord] = []
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SharedNotificationRecord].self, from: data) {
            records = decoded
        }

        // Dedup per requestId
        if records.contains(where: { $0.requestId == requestId }) {
            return
        }

        let record = SharedNotificationRecord(
            title: title,
            body: body,
            date: Date(),
            isRead: false,
            requestId: requestId
        )
        records.insert(record, at: 0)

        // Prune: max 30 giorni
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        records = records.filter { $0.date > cutoff }

        if let encoded = try? JSONEncoder().encode(records) {
            defaults.set(encoded, forKey: key)
        }
    }
}

// MARK: - Shared Model (deve essere identico a quello nell'app principale)

struct SharedNotificationRecord: Codable {
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
