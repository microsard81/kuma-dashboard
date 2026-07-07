import Foundation

/// Appends events to a local CSV file (never overwrites).
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
    func appendEvents(_ events: [(id: String, date: Date, title: String, body: String)]) {
        guard isEnabled, let path = filePath, !path.isEmpty else { return }

        let url = resolveFileURL(path: path)
        guard let url = url else { return }

        // Load already written IDs
        var writtenIds = Set(defaults.stringArray(forKey: writtenIdsKey) ?? [])
        let newEvents = events.filter { !writtenIds.contains($0.id) }
        guard !newEvents.isEmpty else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.timeZone = TimeZone(identifier: "Europe/Rome")

        // Build log lines
        var lines = ""
        for event in newEvents {
            let date = dateFormatter.string(from: event.date)
            let body = event.body.replacingOccurrences(of: "\n", with: " | ")
            lines += "[\(date)] \(event.title)\(body.isEmpty ? "" : " — \(body)")\n"
        }

        // Append to file
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

        // Persist written IDs (keep last 1000 to avoid unbounded growth)
        for event in newEvents {
            writtenIds.insert(event.id)
        }
        let trimmed = Array(writtenIds.suffix(1000))
        defaults.set(trimmed, forKey: writtenIdsKey)
    }

    private func resolveFileURL(path: String) -> URL? {
        // Try security-scoped bookmark first
        if let bookmarkData = defaults.data(forKey: "mac_local_event_log_bookmark") {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale {
                    // Refresh bookmark
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
