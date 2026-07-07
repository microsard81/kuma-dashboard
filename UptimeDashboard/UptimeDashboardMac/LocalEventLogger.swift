import Foundation

/// Appends events to a local log file (never overwrites).
/// Tracks which event IDs have already been written to avoid duplicates.
final class LocalEventLogger {
    static let shared = LocalEventLogger()

    private let defaults = UserDefaults.standard
    private let writtenIdsKey = "mac_local_event_log_written_ids"

    private init() {}

    var isEnabled: Bool {
        defaults.bool(forKey: "mac_local_event_log_enabled")
    }

    private var filePath: String? {
        defaults.string(forKey: "mac_local_event_log_path")
    }

    /// Appends new events to the local log file.
    /// Only writes events whose IDs haven't been written before.
    /// If the file is empty, writes all provided events (backfill).
    func appendEvents(_ events: [(id: String, date: Date, title: String, body: String)]) {
        guard isEnabled, let path = filePath, !path.isEmpty else { return }

        let url = resolveFileURL(path: path)
        guard let url = url else { return }

        // If file is empty, backfill all events (reset written IDs)
        let fileIsEmpty: Bool
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64 {
            fileIsEmpty = size == 0
        } else {
            fileIsEmpty = true
        }

        var writtenIds = Set(defaults.stringArray(forKey: writtenIdsKey) ?? [])

        let newEvents: [(id: String, date: Date, title: String, body: String)]
        if fileIsEmpty {
            writtenIds.removeAll()
            newEvents = events
        } else {
            newEvents = events.filter { !writtenIds.contains($0.id) }
        }

        guard !newEvents.isEmpty else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.timeZone = TimeZone(identifier: "Europe/Rome")

        // Sort oldest first
        let sorted = newEvents.sorted { $0.date < $1.date }
        var lines = ""
        for event in sorted {
            let date = dateFormatter.string(from: event.date)
            let body = event.body.replacingOccurrences(of: "\n", with: " | ")
            lines += "[\(date)] \(event.title)\(body.isEmpty ? "" : " — \(body)")\n"
        }

        if let data = lines.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }

        for event in sorted {
            writtenIds.insert(event.id)
        }
        let trimmed = Array(writtenIds.suffix(1000))
        defaults.set(trimmed, forKey: writtenIdsKey)
    }

    /// Fetches events from server and backfills the log file immediately.
    /// Called when the user enables logging and chooses a file.
    func backfillIfNeeded() {
        guard isEnabled, let path = filePath, !path.isEmpty else { return }

        let baseURL = "https://kuma-dashboard.sundata.cloud"
        guard let apiURL = URL(string: "\(baseURL)/api/events?limit=200") else { return }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"

        Task {
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            struct EventsResponse: Codable {
                let events: [ServerEvent]
            }
            struct ServerEvent: Codable {
                let id: String
                let ts: String
                let type: String
                let name: String
                let detail: String?

                var date: Date {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return formatter.date(from: ts) ?? Date.distantPast
                }
            }

            guard let decoded = try? JSONDecoder().decode(EventsResponse.self, from: data) else { return }

            let events = decoded.events
                .filter { $0.type != "global" }
                .map { (id: $0.id, date: $0.date, title: $0.name, body: $0.detail ?? "") }

            self.appendEvents(events)
        }
    }

    private func resolveFileURL(path: String) -> URL? {
        if let bookmarkData = defaults.data(forKey: "mac_local_event_log_bookmark") {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale {
                    if let newBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        defaults.set(newBookmark, forKey: "mac_local_event_log_bookmark")
                    }
                }
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }
        return URL(fileURLWithPath: path)
    }
}
