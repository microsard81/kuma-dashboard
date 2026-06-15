import Foundation
import Combine
import SwiftUI

// MARK: - Auth State

enum MacAuthState: Equatable {
    case login
    case biometricGate        // Biometric unlock screen
    case changePassword
    case totpSetup(secret: String, uri: String)
    case twoFA
    case authenticated
}

// MARK: - Monitor Model

struct MacMonitor: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let k1: String
    let k2: String
    let k3: String
    let n1: String
    let u1: String
    let finalStatus: String
    let severity: Int
    let link: String?
    let history: [[String: Any]]

    var isDown: Bool { finalStatus == "DOWN" }
    var isMismatch: Bool { !isDown && Set([k1, k2, k3, n1, u1]).count > 1 }

    static func == (lhs: MacMonitor, rhs: MacMonitor) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.finalStatus == rhs.finalStatus
            && lhs.k1 == rhs.k1 && lhs.k2 == rhs.k2 && lhs.k3 == rhs.k3 && lhs.n1 == rhs.n1
            && lhs.u1 == rhs.u1
    }
}

// MARK: - ViewModel

@MainActor
final class MacAppViewModel: ObservableObject {
    @Published var authState: MacAuthState = .login
    @Published var biometricManager: MacBiometricManager
    @Published var monitors: [MacMonitor] = []
    @Published var globalState: String = "GREEN"
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var lastUpdated: Date? = nil

    // MARK: - Sensor properties
    @Published var sensors: [SensorReading] = []
    @Published var sensorThresholds: SensorThresholds?
    @Published var sensorHistory: [String: [SensorHistoryPoint]] = [:]
    @Published var sensorAlerts: SensorAlerts?
    @Published var sensorError: String?

    /// Temperature sensors filtered from the full sensors array.
    var temperatureSensors: [SensorReading] {
        sensors.filter { $0.category == .temperature }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Power sensors filtered from the full sensors array.
    var powerSensors: [SensorReading] {
        sensors.filter { $0.category == .power }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Preferenze
    @Published var themeMode: String
    @Published var textScale: Double
    @Published var refreshInterval: Int  // secondi, 0 = disabilitato
    @Published var sortOrder: String     // "severity", "alphabetical", "globalState"
    @Published var badgeEnabled: Bool
    @Published var notificationsEnabled: Bool
    @Published var notificationThreshold: Int

    func setTheme(_ mode: String) {
        themeMode = mode
        defaults.set(mode, forKey: "mac_theme")
    }

    func setTextScale(_ scale: Double) {
        textScale = scale
        defaults.set(scale, forKey: "mac_text_scale")
    }

    func setRefreshInterval(_ interval: Int) {
        refreshInterval = interval
        defaults.set(interval, forKey: "mac_refresh_interval")
        restartAutoRefresh()
    }

    func setSortOrder(_ order: String) {
        sortOrder = order
        defaults.set(order, forKey: "mac_sort_order")
    }

    func setBadgeEnabled(_ enabled: Bool) {
        badgeEnabled = enabled
        defaults.set(enabled, forKey: "mac_badge_enabled")
        if !enabled {
            NSApplication.shared.dockTile.badgeLabel = nil
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        defaults.set(enabled, forKey: "mac_notifications_enabled")

        if enabled {
            // Re-register for remote notifications
            NSApplication.shared.registerForRemoteNotifications()
        } else {
            // Unsubscribe from backend
            guard let deviceToken = defaults.string(forKey: "mac_apnsDeviceToken"),
                  let apiToken = Bundle.main.object(forInfoDictionaryKey: "WATCH_API_TOKEN") as? String else { return }

            Task {
                do {
                    guard let url = URL(string: "\(baseURL)/api/mac/apns/unsubscribe") else { return }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiToken, forHTTPHeaderField: "X-Watch-Token")

                    let payload: [String: Any] = ["device_token": deviceToken]
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        await MainActor.run {
                            self.errorMessage = "Errore disattivazione notifiche"
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Errore disattivazione notifiche"
                    }
                }
            }

            // Unregister from APNs
            NSApplication.shared.unregisterForRemoteNotifications()
        }
    }

    func setNotificationThreshold(_ value: Int) {
        guard (1...5).contains(value) else { return }
        let previousValue = notificationThreshold
        notificationThreshold = value
        defaults.set(value, forKey: "mac_notification_threshold")

        // Read the stored APNs device token
        guard let deviceToken = defaults.string(forKey: "mac_apnsDeviceToken") else { return }

        // Read the API token for X-Watch-Token authentication
        guard let apiToken = Bundle.main.object(forInfoDictionaryKey: "WATCH_API_TOKEN") as? String else { return }

        Task {
            do {
                guard let url = URL(string: "\(baseURL)/api/mac/apns/threshold") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(apiToken, forHTTPHeaderField: "X-Watch-Token")

                let payload: [String: Any] = [
                    "device_token": deviceToken,
                    "threshold": value
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else {
                    // Restore previous value on error
                    await MainActor.run {
                        self.notificationThreshold = previousValue
                        self.defaults.set(previousValue, forKey: "mac_notification_threshold")
                        self.errorMessage = "Errore aggiornamento soglia notifica"
                    }
                    return
                }
            } catch {
                // Restore previous value on network error
                await MainActor.run {
                    self.notificationThreshold = previousValue
                    self.defaults.set(previousValue, forKey: "mac_notification_threshold")
                    self.errorMessage = "Errore aggiornamento soglia notifica"
                }
            }
        }
    }

    private var refreshTimer: Timer?
    private let baseURL: String
    private let defaults = UserDefaults.standard

    // Session cookie storage
    private var sessionCookies: [HTTPCookie] = []

    init() {
        self.baseURL = "https://kuma-dashboard.sundata.cloud"
        self.themeMode = defaults.string(forKey: "mac_theme") ?? "dark"
        self.textScale = defaults.double(forKey: "mac_text_scale").nonZero ?? 1.0
        self.refreshInterval = defaults.object(forKey: "mac_refresh_interval") as? Int ?? 60
        self.sortOrder = defaults.string(forKey: "mac_sort_order") ?? "severity"
        self.badgeEnabled = defaults.object(forKey: "mac_badge_enabled") as? Bool ?? true
        self.notificationsEnabled = defaults.object(forKey: "mac_notifications_enabled") as? Bool ?? true

        // Read notificationThreshold with safe fallback (default: 1)
        let storedThreshold = defaults.object(forKey: "mac_notification_threshold") as? Int ?? 1
        self.notificationThreshold = (1...5).contains(storedThreshold) ? storedThreshold : 1

        // Initialize biometric manager
        self.biometricManager = MacBiometricManager(
            keychainStore: MacKeychainStore(),
            baseURL: "https://kuma-dashboard.sundata.cloud"
        )

        // Check biometric state first
        evaluateBiometricState()

        // Only check "remember me" if biometric didn't set the state
        if authState == .login {
            if defaults.bool(forKey: "mac_remember_me"),
               let _ = defaults.string(forKey: "mac_session_active") {
                authState = .authenticated
                restoreCookies()
            }
        }
    }

    // MARK: - Login

    func login(username: String, password: String, rememberMe: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/api/login") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["username": username, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            saveCookies(from: response)

            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 401 {
                errorMessage = "Credenziali non valide"
                return
            }
            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                errorMessage = "Errore di connessione"
                return
            }

            if rememberMe {
                defaults.set(true, forKey: "mac_remember_me")
                defaults.set("active", forKey: "mac_session_active")
                persistCookies()
            }

            if let next = json["next"] as? String {
                switch next {
                case "change_password":
                    authState = .changePassword
                case "totp_setup":
                    let secret = json["totp_secret"] as? String ?? ""
                    let uri = json["totp_uri"] as? String ?? ""
                    authState = .totpSetup(secret: secret, uri: uri)
                case "2fa":
                    authState = .twoFA
                default:
                    authState = .authenticated
                }
            } else {
                authState = .authenticated
            }
        } catch {
            errorMessage = "Errore di connessione"
        }
    }

    // MARK: - Change Password

    func changePassword(newPassword: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/api/change-password") else { return }
        var request = makeAuthenticatedRequest(url: url, method: "POST")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["new_password": newPassword])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            saveCookies(from: response)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 400,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                errorMessage = error
                return
            }

            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                errorMessage = "Errore"
                return
            }

            handleNextStep(json)
        } catch {
            errorMessage = "Errore di connessione"
        }
    }

    // MARK: - TOTP Enroll

    func enrollTOTP(code: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/api/totp/enroll") else { return }
        var request = makeAuthenticatedRequest(url: url, method: "POST")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            saveCookies(from: response)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 401 {
                errorMessage = "Codice non valido"
                return
            }
            guard http.statusCode == 200 else {
                errorMessage = "Errore"
                return
            }

            persistCookies()
            authState = .authenticated
        } catch {
            errorMessage = "Errore di connessione"
        }
    }

    // MARK: - Verify 2FA

    func verify2FA(code: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/api/2fa") else { return }
        var request = makeAuthenticatedRequest(url: url, method: "POST")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            saveCookies(from: response)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 401 {
                errorMessage = "Codice non valido"
                return
            }
            guard http.statusCode == 200 else {
                errorMessage = "Errore"
                return
            }

            persistCookies()
            authState = .authenticated
        } catch {
            errorMessage = "Errore di connessione"
        }
    }

    // MARK: - Fetch Dashboard

    func fetchDashboard() async {
        guard let url = URL(string: "\(baseURL)/api/dashboard-data") else { return }
        let request = makeAuthenticatedRequest(url: url, method: "GET")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            saveCookies(from: response)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 302 || http.statusCode == 401 {
                // Sessione scaduta
                logout()
                return
            }

            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return }

            monitors = items.compactMap { dict in
                guard let name = dict["name"] as? String,
                      let k1 = dict["k1"] as? String,
                      let k2 = dict["k2"] as? String,
                      let k3 = dict["k3"] as? String,
                      let n1 = dict["n1"] as? String,
                      let final_ = dict["final"] as? String,
                      let severity = dict["severity"] as? Int else { return nil }
                let u1 = dict["u1"] as? String ?? "UP"
                let history = dict["history"] as? [[String: Any]] ?? []
                return MacMonitor(name: name, k1: k1, k2: k2, k3: k3, n1: n1, u1: u1,
                                  finalStatus: final_, severity: severity,
                                  link: dict["link"] as? String,
                                  history: history)
            }
            // Ordina per gravità (severity decrescente), poi alfabetico dentro ogni gruppo
            monitors.sort {
                if $0.severity != $1.severity {
                    return $0.severity > $1.severity
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            globalState = json["global_state"] as? String ?? "GREEN"
            lastUpdated = Date()
            updateBadge()
        } catch {
            // Silently fail
        }

        // Fetch sensor data independently (graceful degradation)
        await fetchSensorData()
    }

    // MARK: - Fetch Sensor Data

    /// Fetches sensor data from `/api/watch-data` using the WATCH_API_TOKEN from Info.plist.
    /// On failure, sets sensorError and clears sensor data gracefully.
    func fetchSensorData() async {
        guard let apiToken = Bundle.main.object(forInfoDictionaryKey: "WATCH_API_TOKEN") as? String,
              !apiToken.isEmpty,
              let url = URL(string: "\(baseURL)/api/watch-data") else {
            // No token configured — silently skip sensor fetch
            return
        }

        var request = URLRequest(url: url)
        request.setValue(apiToken, forHTTPHeaderField: "X-Watch-Token")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                sensorError = "Errore connessione sensori"
                return
            }
            parseSensorPayload(data: data)
        } catch {
            sensorError = "Errore connessione sensori"
        }
    }

    /// Parses sensor fields from the `/api/watch-data` JSON response.
    /// Missing fields are treated as empty (graceful degradation).
    private func parseSensorPayload(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sensorError = "Errore decodifica sensori"
            return
        }

        let decoder = JSONDecoder()

        // Parse sensors array
        if let sensorsArray = json["sensors"] {
            if let sensorsData = try? JSONSerialization.data(withJSONObject: sensorsArray),
               let decoded = try? decoder.decode([SensorReading].self, from: sensorsData) {
                sensors = decoded
            } else {
                sensors = []
            }
        } else {
            sensors = []
        }

        // Parse thresholds
        if let thresholdsObj = json["thresholds"] {
            if let thresholdsData = try? JSONSerialization.data(withJSONObject: thresholdsObj),
               let decoded = try? decoder.decode(SensorThresholds.self, from: thresholdsData) {
                sensorThresholds = decoded
            } else {
                sensorThresholds = nil
            }
        } else {
            sensorThresholds = nil
        }

        // Parse sensor_history
        if let historyObj = json["sensor_history"] {
            if let historyData = try? JSONSerialization.data(withJSONObject: historyObj),
               let decoded = try? decoder.decode([String: [SensorHistoryPoint]].self, from: historyData) {
                sensorHistory = decoded
            } else {
                sensorHistory = [:]
            }
        } else {
            sensorHistory = [:]
        }

        // Parse sensor_alerts
        if let alertsObj = json["sensor_alerts"] {
            if let alertsData = try? JSONSerialization.data(withJSONObject: alertsObj),
               let decoded = try? decoder.decode(SensorAlerts.self, from: alertsData) {
                sensorAlerts = decoded
            } else {
                sensorAlerts = nil
            }
        } else {
            sensorAlerts = nil
        }

        // Parse sensor_error
        if let errorStr = json["sensor_error"] as? String {
            sensorError = errorStr
        } else {
            sensorError = nil
        }
    }

    // MARK: - Auto Refresh

    func startAutoRefresh() {
        stopAutoRefresh()
        Task { await fetchDashboard() }
        guard refreshInterval > 0 else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshInterval), repeats: true) { [weak self] _ in
            Task { await self?.fetchDashboard() }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func restartAutoRefresh() {
        guard authState == .authenticated else { return }
        startAutoRefresh()
    }

    private func updateBadge() {
        let count = monitors.filter { $0.isDown || $0.isMismatch }.count
        if badgeEnabled && count > 0 {
            NSApplication.shared.dockTile.badgeLabel = "\(count)"
        } else {
            NSApplication.shared.dockTile.badgeLabel = nil
        }
    }

    // MARK: - Logout

    func logout() {
        stopAutoRefresh()
        monitors = []
        biometricManager.removeToken()  // Clear biometric token on logout
        defaults.removeObject(forKey: "mac_remember_me")
        defaults.removeObject(forKey: "mac_session_active")
        defaults.removeObject(forKey: "mac_cookies")
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        sessionCookies = []
        authState = .login
    }

    // MARK: - Biometric Authentication

    /// Called during init to determine if biometric gate should be shown.
    /// If biometrics available AND token exists → .biometricGate
    /// Otherwise → .login (caller may override with "remember me")
    func evaluateBiometricState() {
        let method = biometricManager.checkAvailability()
        if method != .none && biometricManager.hasEnrolledToken() {
            authState = .biometricGate
        }
        // If method is .none or no token, leave as .login
    }

    /// Called from MacBiometricGateView to initiate biometric auth.
    func authenticateWithBiometrics() async {
        let result = await biometricManager.authenticate()

        switch result {
        case .success:
            authState = .authenticated
            // Refresh token if needed (non-blocking)
            if let (username, _) = try? MacKeychainStore().loadToken() {
                Task {
                    await biometricManager.refreshTokenIfNeeded(username: username)
                }
            }
        case .cancelled:
            // Do nothing — user can retry or tap fallback
            break
        case .failed:
            // Error is displayed by MacBiometricGateView via biometricManager state
            break
        case .tokenExpired:
            authState = .login
        case .networkError:
            // Error is displayed by MacBiometricGateView
            break
        }
    }

    /// Called after successful full login to enroll a biometric token.
    /// Fire-and-forget: failures don't block the session.
    func enrollBiometricToken(username: String) async {
        _ = await biometricManager.enrollToken(username: username)
    }

    // MARK: - Cookie Management

    private func makeAuthenticatedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // I cookie vengono gestiti automaticamente da HTTPCookieStorage
        return request
    }

    private func saveCookies(from response: URLResponse) {
        guard let http = response as? HTTPURLResponse,
              let url = response.url,
              let headerFields = http.allHeaderFields as? [String: String] else { return }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        sessionCookies = HTTPCookieStorage.shared.cookies ?? []
    }

    private func persistCookies() {
        let cookieData = sessionCookies.compactMap { cookie -> [String: String]? in
            return [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path,
            ]
        }
        if let json = try? JSONEncoder().encode(cookieData) {
            defaults.set(json, forKey: "mac_cookies")
        }
    }

    private func restoreCookies() {
        guard let data = defaults.data(forKey: "mac_cookies"),
              let cookieData = try? JSONDecoder().decode([[String: String]].self, from: data) else { return }
        for dict in cookieData {
            guard let name = dict["name"], let value = dict["value"],
                  let domain = dict["domain"], let path = dict["path"] else { continue }
            let props: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: path
            ]
            if let cookie = HTTPCookie(properties: props) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
        sessionCookies = HTTPCookieStorage.shared.cookies ?? []
    }

    // MARK: - Helpers

    private func handleNextStep(_ json: [String: Any]) {
        if let next = json["next"] as? String {
            switch next {
            case "totp_setup":
                let secret = json["totp_secret"] as? String ?? ""
                let uri = json["totp_uri"] as? String ?? ""
                authState = .totpSetup(secret: secret, uri: uri)
            case "2fa":
                authState = .twoFA
            default:
                authState = .authenticated
            }
        } else {
            authState = .authenticated
        }
    }
}

private extension Double {
    /// Returns nil if the value is 0 (UserDefaults returns 0 for missing keys).
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
