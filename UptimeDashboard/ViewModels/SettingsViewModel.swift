import Foundation
import SwiftUI
import UserNotifications

enum ThemeMode: String, CaseIterable {
    case auto = "auto"
    case light = "light"
    case dark = "dark"

    var next: ThemeMode {
        switch self {
        case .auto: return .light
        case .light: return .dark
        case .dark: return .auto
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Criterio di ordinamento dei monitor
enum SortOrder: String, CaseIterable {
    case severity = "severity"
    case alphabetical = "alphabetical"
    case globalState = "globalState"

    var displayName: String {
        switch self {
        case .severity: return "Per gravità"
        case .alphabetical: return "Alfabetico"
        case .globalState: return "Per stato globale"
        }
    }
}

/// Intervallo di auto-refresh
enum RefreshInterval: String, CaseIterable {
    case ten = "10"
    case thirty = "30"
    case sixty = "60"
    case disabled = "disabled"

    var displayName: String {
        switch self {
        case .ten: return "10 secondi"
        case .thirty: return "30 secondi"
        case .sixty: return "60 secondi"
        case .disabled: return "Disabilitato"
        }
    }

    /// Intervallo in secondi, nil se disabilitato
    var seconds: TimeInterval? {
        switch self {
        case .ten: return 10
        case .thirty: return 30
        case .sixty: return 60
        case .disabled: return nil
        }
    }
}

/// Stato della connessione al backend
enum ConnectionStatus {
    case checking
    case connected
    case disconnected
}

@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - Published preferences
    @Published var themeMode: ThemeMode
    @Published var sortOrder: SortOrder
    @Published var refreshInterval: RefreshInterval
    @Published var biometricEnabled: Bool
    @Published var hapticEnabled: Bool
    @Published var badgeEnabled: Bool
    @Published var notificationsEnabled: Bool = false
    @Published var notificationPermissionDenied: Bool = false
    @Published var connectionStatus: ConnectionStatus = .checking

    // MARK: - Computed properties
    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
    }

    var backendHost: String {
        AppConfig.baseURL.host() ?? "N/A"
    }

    // MARK: - Dependencies
    private let defaults: UserDefaults
    private let notificationManager: NotificationManagerProtocol
    private let network: NetworkClientProtocol?

    // MARK: - UserDefaults keys
    private let themeModeKey = "themeMode"
    private let sortOrderKey = "sortOrder"
    private let refreshIntervalKey = "refreshInterval"
    private let biometricEnabledKey = "biometricEnabled"
    private let hapticEnabledKey = "hapticEnabled"
    private let badgeEnabledKey = "badgeEnabled"

    // MARK: - Init
    init(defaults: UserDefaults = .standard,
         notificationManager: NotificationManagerProtocol = NotificationManager.shared,
         network: NetworkClientProtocol? = nil) {
        self.defaults = defaults
        self.notificationManager = notificationManager
        self.network = network

        // Read themeMode with safe fallback
        if let raw = defaults.string(forKey: "themeMode"),
           let saved = ThemeMode(rawValue: raw) {
            self.themeMode = saved
        } else {
            self.themeMode = .dark
        }

        // Read sortOrder with safe fallback
        if let raw = defaults.string(forKey: "sortOrder"),
           let saved = SortOrder(rawValue: raw) {
            self.sortOrder = saved
        } else {
            self.sortOrder = .severity
        }

        // Read refreshInterval with safe fallback
        if let raw = defaults.string(forKey: "refreshInterval"),
           let saved = RefreshInterval(rawValue: raw) {
            self.refreshInterval = saved
        } else {
            self.refreshInterval = .sixty
        }

        // Read biometricEnabled with safe fallback (default: true)
        self.biometricEnabled = defaults.object(forKey: "biometricEnabled") as? Bool ?? true

        // Read hapticEnabled with safe fallback (default: true)
        self.hapticEnabled = defaults.object(forKey: "hapticEnabled") as? Bool ?? true

        // Read badgeEnabled with safe fallback (default: true)
        self.badgeEnabled = defaults.object(forKey: "badgeEnabled") as? Bool ?? true
    }

    // MARK: - Theme actions

    func cycleTheme() {
        themeMode = themeMode.next
        defaults.set(themeMode.rawValue, forKey: themeModeKey)
    }

    func setTheme(_ mode: ThemeMode) {
        themeMode = mode
        defaults.set(mode.rawValue, forKey: themeModeKey)
    }

    // MARK: - Sort order actions

    func setSortOrder(_ order: SortOrder) {
        sortOrder = order
        defaults.set(order.rawValue, forKey: sortOrderKey)
    }

    // MARK: - Refresh interval actions

    func setRefreshInterval(_ interval: RefreshInterval) {
        refreshInterval = interval
        defaults.set(interval.rawValue, forKey: refreshIntervalKey)
    }

    // MARK: - Biometric actions

    func setBiometricEnabled(_ enabled: Bool) {
        biometricEnabled = enabled
        defaults.set(enabled, forKey: biometricEnabledKey)
    }

    func setHapticEnabled(_ enabled: Bool) {
        hapticEnabled = enabled
        defaults.set(enabled, forKey: hapticEnabledKey)
    }

    func setBadgeEnabled(_ enabled: Bool) {
        badgeEnabled = enabled
        defaults.set(enabled, forKey: badgeEnabledKey)
        if !enabled {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        }
    }

    // MARK: - Notification actions

    func toggleNotifications() async {
        if notificationsEnabled {
            // Turning off
            try? await notificationManager.unregister()
            notificationsEnabled = false
        } else {
            // Turning on — request permission first
            let granted = await notificationManager.requestPermission()
            if granted {
                notificationManager.registerForRemoteNotifications()
                notificationsEnabled = true
            } else {
                notificationsEnabled = false
                notificationPermissionDenied = true
            }
        }
    }

    // MARK: - Connection check

    func checkConnectionStatus() async {
        connectionStatus = .checking
        guard let network else {
            connectionStatus = .disconnected
            return
        }
        do {
            _ = try await network.fetchDashboardData()
            connectionStatus = .connected
        } catch {
            connectionStatus = .disconnected
        }
    }

    // MARK: - Notification permission check

    func checkNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .denied:
            notificationPermissionDenied = true
            notificationsEnabled = false
        case .authorized:
            notificationPermissionDenied = false
            notificationsEnabled = true
        default:
            notificationPermissionDenied = false
        }
    }
}
