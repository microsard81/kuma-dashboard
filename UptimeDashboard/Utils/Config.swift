import Foundation
import OSLog

// Feature: ios-native-app
// Requisiti: 9.1, 12.3, 12.4

enum AppConfig {
    /// URL base del backend Flask, letto da Info.plist (chiave BACKEND_BASE_URL).
    /// Deve usare schema https:// — qualsiasi altro schema causa un fatalError.
    static let baseURL: URL = {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "BACKEND_BASE_URL") as? String,
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            fatalError("BACKEND_BASE_URL non configurato in Info.plist")
        }
        guard url.scheme == "https" else {
            #if DEBUG
            fatalError("BACKEND_BASE_URL deve usare schema https://")
            #else
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "UptimeDashboard", category: "Config")
            logger.error("BACKEND_BASE_URL non usa schema https:// — connessione rifiutata")
            fatalError("BACKEND_BASE_URL deve usare schema https://")
            #endif
        }
        return url
    }()
}
