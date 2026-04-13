import Foundation
import SwiftUI

// MARK: - Auth State

enum MacAuthState: Equatable {
    case login
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
    let finalStatus: String
    let severity: Int
    let link: String?

    var isDown: Bool { finalStatus == "DOWN" }
    var isMismatch: Bool { !isDown && Set([k1, k2, k3, n1]).count > 1 }
}

// MARK: - ViewModel

@MainActor
final class MacAppViewModel: ObservableObject {
    @Published var authState: MacAuthState = .login
    @Published var monitors: [MacMonitor] = []
    @Published var globalState: String = "GREEN"
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var lastUpdated: Date? = nil

    private var refreshTimer: Timer?
    private let baseURL: String
    private let defaults = UserDefaults.standard

    // Session cookie storage
    private var sessionCookies: [HTTPCookie] = []

    init() {
        self.baseURL = "https://kuma-dashboard.sundata.cloud"

        // Ripristina sessione se "Ricordami" era attivo
        if defaults.bool(forKey: "mac_remember_me"),
           let _ = defaults.string(forKey: "mac_session_active") {
            // Prova a validare la sessione al prossimo fetch
            authState = .authenticated
            restoreCookies()
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
                return MacMonitor(name: name, k1: k1, k2: k2, k3: k3, n1: n1,
                                  finalStatus: final_, severity: severity,
                                  link: dict["link"] as? String)
            }
            globalState = json["global_state"] as? String ?? "GREEN"
            lastUpdated = Date()
        } catch {
            // Silently fail
        }
    }

    // MARK: - Auto Refresh

    func startAutoRefresh() {
        stopAutoRefresh()
        Task { await fetchDashboard() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.fetchDashboard() }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Logout

    func logout() {
        stopAutoRefresh()
        monitors = []
        defaults.removeObject(forKey: "mac_remember_me")
        defaults.removeObject(forKey: "mac_session_active")
        defaults.removeObject(forKey: "mac_cookies")
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        sessionCookies = []
        authState = .login
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
