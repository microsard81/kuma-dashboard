// EventLogService.swift
// Fetches event history from the backend API and manages local read state per-device.
// Used by both iOS and macOS apps to show the complete event timeline.

import Foundation

// MARK: - Server Event Model

/// An event as returned by the backend `/api/events` endpoint.
struct ServerEvent: Codable, Identifiable {
    let id: String
    let ts: String
    let type: String       // "global", "sensor", "monitor"
    let title: String
    let body: String
    let state: String
    let name: String
    let from: String
    let to: String
    let severity: Int

    /// Parsed timestamp
    var date: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: ts) ?? Date.distantPast
    }
}

/// Response from `/api/events`
struct EventsResponse: Codable {
    let events: [ServerEvent]
    let count: Int
}

// MARK: - Display Event (combines server data + local read state)

struct EventRecord: Identifiable {
    let id: String
    let title: String
    let body: String
    let date: Date
    let state: String
    let type: String
    let severity: Int
    var isRead: Bool
}

// MARK: - EventLogService

@MainActor
final class EventLogService: ObservableObject {
    static let shared = EventLogService()

    @Published var events: [EventRecord] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private let readStateKey = "event_read_state"
    private let appGroupId = "group.cloud.sundata.uptimeDashboard"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? UserDefaults.standard
    }

    var unreadCount: Int {
        events.filter { !$0.isRead }.count
    }

    private init() {}

    // MARK: - Fetch from Backend

    /// Fetches events from the server using session cookies (same auth as dashboard).
    func fetchEvents(baseURL: URL, session: URLSession? = nil) async {
        isLoading = true
        lastError = nil

        let url = baseURL.appendingPathComponent("api/events")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: "200")]

        guard let requestURL = components?.url else {
            lastError = "URL non valido"
            isLoading = false
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"

        let urlSession = session ?? URLSession.shared

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                lastError = "Risposta non valida"
                isLoading = false
                return
            }

            guard http.statusCode == 200 else {
                lastError = "Errore \(http.statusCode)"
                isLoading = false
                return
            }

            let decoder = JSONDecoder()
            let eventsResponse = try decoder.decode(EventsResponse.self, from: data)

            // Merge with local read state
            let readState = loadReadState()
            self.events = eventsResponse.events.map { serverEvent in
                EventRecord(
                    id: serverEvent.id,
                    title: serverEvent.title,
                    body: serverEvent.body,
                    date: serverEvent.date,
                    state: serverEvent.state,
                    type: serverEvent.type,
                    severity: serverEvent.severity,
                    isRead: readState.contains(serverEvent.id)
                )
            }
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Read State Management (local per-device)

    func markAsRead(id: String) {
        var state = loadReadState()
        state.insert(id)
        saveReadState(state)
        if let idx = events.firstIndex(where: { $0.id == id }) {
            events[idx].isRead = true
        }
    }

    func markAsUnread(id: String) {
        var state = loadReadState()
        state.remove(id)
        saveReadState(state)
        if let idx = events.firstIndex(where: { $0.id == id }) {
            events[idx].isRead = false
        }
    }

    func markAllAsRead() {
        var state = loadReadState()
        for event in events {
            state.insert(event.id)
        }
        saveReadState(state)
        for idx in events.indices {
            events[idx].isRead = true
        }
    }

    // MARK: - Private

    private func loadReadState() -> Set<String> {
        guard let array = defaults.stringArray(forKey: readStateKey) else {
            return []
        }
        return Set(array)
    }

    private func saveReadState(_ state: Set<String>) {
        // Prune: keep only IDs that exist in current events (avoid unbounded growth)
        let validIds = Set(events.map { $0.id })
        let pruned = state.intersection(validIds)
        defaults.set(Array(pruned), forKey: readStateKey)
    }
}
