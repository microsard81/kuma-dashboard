// Feature: native-apps-sensor-integration

import SwiftUI

// MARK: - Server Event Models (inline per target macOS)

private struct MacServerEvent: Codable, Identifiable {
    let id: String
    let ts: String
    let type: String
    let title: String
    let body: String
    let state: String
    let name: String
    let from: String
    let to: String
    let severity: Int

    var date: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: ts) ?? Date.distantPast
    }
}

private struct MacEventsResponse: Codable {
    let events: [MacServerEvent]
    let count: Int
}

// MARK: - Display Record

private struct MacEventRecord: Identifiable {
    let id: String
    let title: String
    let body: String
    let date: Date
    let severity: Int
    var isRead: Bool
}

// MARK: - NotificationHistoryView

/// Storico eventi completo dal backend. Stato letto/non letto locale per dispositivo.
struct NotificationHistoryView: View {
    @State private var events: [MacEventRecord] = []
    @State private var isLoading = false

    private let appGroupId = "group.cloud.sundata.uptimeDashboard"
    private let readStateKey = "mac_event_read_state"
    private let baseURL = "https://kuma-dashboard.sundata.cloud"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? UserDefaults.standard
    }

    private var unreadEvents: [MacEventRecord] {
        events.filter { !$0.isRead }
    }

    private var readEvents: [MacEventRecord] {
        events.filter { $0.isRead }
    }

    var body: some View {
        Group {
            if isLoading && events.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Caricamento eventi...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bell.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Nessun evento")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Gli eventi di stato appariranno qui")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !unreadEvents.isEmpty {
                        Section {
                            ForEach(unreadEvents) { event in
                                MacEventRow(event: event)
                                    .listRowBackground(Color.blue.opacity(0.08))
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            markAsRead(id: event.id)
                                        } label: {
                                            Label("Letta", systemImage: "envelope.open")
                                        }
                                        .tint(.blue)
                                    }
                            }
                        } header: {
                            Text("Non lette (\(unreadEvents.count))")
                        }
                    }

                    if !readEvents.isEmpty {
                        Section {
                            ForEach(readEvents) { event in
                                MacEventRow(event: event)
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            markAsUnread(id: event.id)
                                        } label: {
                                            Label("Non letta", systemImage: "envelope.badge")
                                        }
                                        .tint(.blue)
                                    }
                            }
                        } header: {
                            if !unreadEvents.isEmpty {
                                Text("Lette")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await fetchEvents()
                }
            }
        }
        .navigationTitle("Eventi")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if !unreadEvents.isEmpty {
                    Button {
                        markAllAsRead()
                    } label: {
                        Image(systemName: "envelope.open")
                    }
                    .help("Segna tutte come lette")
                }
            }
        }
        .task { await fetchEvents() }
    }

    // MARK: - Fetch

    private func fetchEvents() async {
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/api/events?limit=200") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            let decoded = try JSONDecoder().decode(MacEventsResponse.self, from: data)
            let readState = loadReadState()

            events = decoded.events.map { serverEvent in
                MacEventRecord(
                    id: serverEvent.id,
                    title: serverEvent.title,
                    body: serverEvent.body,
                    date: serverEvent.date,
                    severity: serverEvent.severity,
                    isRead: readState.contains(serverEvent.id)
                )
            }
        } catch {
            // Silently fail — show existing data
        }
    }

    // MARK: - Read State (locale per dispositivo)

    private func markAsRead(id: String) {
        var state = loadReadState()
        state.insert(id)
        saveReadState(state)
        if let idx = events.firstIndex(where: { $0.id == id }) {
            events[idx].isRead = true
        }
    }

    private func markAsUnread(id: String) {
        var state = loadReadState()
        state.remove(id)
        saveReadState(state)
        if let idx = events.firstIndex(where: { $0.id == id }) {
            events[idx].isRead = false
        }
    }

    private func markAllAsRead() {
        var state = loadReadState()
        for event in events { state.insert(event.id) }
        saveReadState(state)
        for idx in events.indices { events[idx].isRead = true }
    }

    private func loadReadState() -> Set<String> {
        guard let array = defaults.stringArray(forKey: readStateKey) else { return [] }
        return Set(array)
    }

    private func saveReadState(_ state: Set<String>) {
        let validIds = Set(events.map { $0.id })
        let pruned = state.intersection(validIds)
        defaults.set(Array(pruned), forKey: readStateKey)
    }
}

// MARK: - MacEventRow

private struct MacEventRow: View {
    let event: MacEventRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !event.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
                Text(event.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(formatDate(event.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if !event.body.isEmpty {
                Text(event.body)
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
