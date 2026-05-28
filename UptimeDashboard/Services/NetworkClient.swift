import Foundation

// Feature: ios-native-app
// Requisiti: 1.2, 1.6, 2.2, 3.1, 9.2, 9.4, 11.2, 12.3

// MARK: - Errors
enum NetworkError: Error, Equatable {
    case sessionExpired
    case unauthorized
    case invalidResponse(statusCode: Int)
    case validationError(message: String)
    case decodingError(Error)
    case networkError(Error)
    case insecureURL

    static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.sessionExpired, .sessionExpired): return true
        case (.unauthorized, .unauthorized): return true
        case (.insecureURL, .insecureURL): return true
        case (.invalidResponse(let a), .invalidResponse(let b)): return a == b
        case (.validationError(let a), .validationError(let b)): return a == b
        case (.decodingError, .decodingError): return true
        case (.networkError, .networkError): return true
        default: return false
        }
    }
}

// MARK: - LoginResult
enum LoginResult: Equatable {
    case requires2FA
    case requiresTOTPSetup(secret: String, uri: String)
    case requiresPasswordChange
    case success
}

// MARK: - Protocol
protocol NetworkClientProtocol {
    func login(username: String, password: String) async throws -> LoginResult
    func changePassword(newPassword: String) async throws -> LoginResult
    func verify2FA(code: String) async throws -> Bool
    func enrollTOTP(code: String) async throws -> Bool
    func logout() async throws
    func fetchDashboardData() async throws -> DashboardResponse
    func subscribeAPNs(deviceToken: String, deviceId: String) async throws
    func unsubscribeAPNs(deviceToken: String) async throws
    func getBiometricToken() async throws -> String
    func biometricLogin(username: String, biometricToken: String) async throws
    func fetchSensorData() async throws -> Data
}

// MARK: - Redirect-aware delegate
/// URLSession delegate that intercepts redirects so we can detect
/// Flask's 302 → /login (session expired) and 302 → /2fa or / (login flow).
final class RedirectCapturingDelegate: NSObject, URLSessionTaskDelegate {
    /// The final URL after all redirects (nil if no redirect occurred).
    var finalURL: URL?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Record the redirect destination but do NOT follow it.
        finalURL = request.url
        completionHandler(nil)
    }
}

// MARK: - NetworkClient
final class NetworkClient: NetworkClientProtocol {

    // MARK: - Dependencies (injectable for testing)
    let session: URLSession
    let baseURL: URL

    // MARK: - Init
    /// Designated initialiser — validates that `baseURL` uses https://.
    init(baseURL: URL, session: URLSession? = nil) throws {
        guard baseURL.scheme == "https" else {
            throw NetworkError.insecureURL
        }
        self.baseURL = baseURL

        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = HTTPCookieStorage.shared
            config.httpShouldSetCookies = true
            config.httpCookieAcceptPolicy = .always
            // We handle redirects manually via the delegate
            self.session = URLSession(configuration: config)
        }
    }

    /// Convenience initialiser that reads `AppConfig.baseURL`.
    convenience init() throws {
        try self.init(baseURL: AppConfig.baseURL)
    }

    // MARK: - login
    func login(username: String, password: String) async throws -> LoginResult {
        let url = baseURL.appendingPathComponent("api/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["username": username, "password": password]
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await performRequest(request, session: session)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse(statusCode: 0)
        }

        if http.statusCode == 401 { throw NetworkError.unauthorized }
        guard http.statusCode == 200 else {
            throw NetworkError.invalidResponse(statusCode: http.statusCode)
        }

        // Decodifica flessibile — "next" può essere presente o meno
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let next = json["next"] as? String {
            if next == "change_password" {
                return .requiresPasswordChange
            }
            if next == "totp_setup",
               let secret = json["totp_secret"] as? String,
               let uri = json["totp_uri"] as? String {
                return .requiresTOTPSetup(secret: secret, uri: uri)
            }
            if next == "2fa" {
                return .requires2FA
            }
        }
        return .success
    }

    // MARK: - changePassword
    func changePassword(newPassword: String) async throws -> LoginResult {
        let url = baseURL.appendingPathComponent("api/change-password")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["new_password": newPassword])

        let (data, response) = try await performRequest(request, session: session)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse(statusCode: 0)
        }

        if http.statusCode == 400 {
            // Estrai il messaggio di errore dal server
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMsg = json["error"] as? String {
                throw NetworkError.validationError(message: errorMsg)
            }
            throw NetworkError.invalidResponse(statusCode: 400)
        }
        if http.statusCode == 401 { throw NetworkError.unauthorized }
        guard http.statusCode == 200 else {
            throw NetworkError.invalidResponse(statusCode: http.statusCode)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let next = json["next"] as? String {
            if next == "totp_setup",
               let secret = json["totp_secret"] as? String,
               let uri = json["totp_uri"] as? String {
                return .requiresTOTPSetup(secret: secret, uri: uri)
            }
            if next == "2fa" {
                return .requires2FA
            }
        }
        return .success
    }

    // MARK: - verify2FA
    func verify2FA(code: String) async throws -> Bool {
        let url = baseURL.appendingPathComponent("api/2fa")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["code": code])

        let (data, response) = try await performRequest(request, session: session)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse(statusCode: 0)
        }

        if http.statusCode == 401 { return false }
        guard http.statusCode == 200 else {
            throw NetworkError.invalidResponse(statusCode: http.statusCode)
        }

        // Salva il token biometrico se presente nella risposta
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let biometricToken = json["biometric_token"] as? String,
           let username = json["username"] as? String {
            _pendingBiometricToken = biometricToken
            _pendingUsername = username
        }

        return true
    }

    // Token biometrico ricevuto dopo il 2FA — letto da AuthViewModel
    var _pendingBiometricToken: String? = nil
    var _pendingUsername: String? = nil

    // MARK: - enrollTOTP
    func enrollTOTP(code: String) async throws -> Bool {
        let url = baseURL.appendingPathComponent("api/totp/enroll")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["code": code])

        let (data, response) = try await performRequest(request, session: session)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse(statusCode: 0)
        }

        if http.statusCode == 401 { return false }
        guard http.statusCode == 200 else {
            throw NetworkError.invalidResponse(statusCode: http.statusCode)
        }

        // Salva il token biometrico se presente
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let biometricToken = json["biometric_token"] as? String,
           let username = json["username"] as? String {
            _pendingBiometricToken = biometricToken
            _pendingUsername = username
        }

        return true
    }

    // MARK: - logout
    func logout() async throws {
        let url = baseURL.appendingPathComponent("logout")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (_, _) = try await performRequest(request, session: session)
    }

    // MARK: - fetchDashboardData
    func fetchDashboardData() async throws -> DashboardResponse {
        let url = baseURL.appendingPathComponent("api/dashboard-data")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let delegate = RedirectCapturingDelegate()
        let delegateSession = makeSessionWithDelegate(delegate)

        let (data, response) = try await performRequest(request, session: delegateSession)

        // Detect session expiry: redirect to /login
        if let destination = delegate.finalURL, destination.path.hasPrefix("/login") {
            postSessionExpiredNotification()
            throw NetworkError.sessionExpired
        }

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse(statusCode: 0)
        }

        if http.statusCode == 302 {
            if let location = http.value(forHTTPHeaderField: "Location"),
               location.contains("/login") {
                postSessionExpiredNotification()
                throw NetworkError.sessionExpired
            }
        }

        guard http.statusCode == 200 else {
            throw NetworkError.invalidResponse(statusCode: http.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(DashboardResponse.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    // MARK: - subscribeAPNs
    func subscribeAPNs(deviceToken: String, deviceId: String) async throws {
        let url = baseURL.appendingPathComponent("push/apns/subscribe")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Rileva automaticamente l'ambiente: le app Xcode usano sandbox, TestFlight/AppStore usano production
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif

        // Includi la soglia notifica corrente (salvata in UserDefaults)
        let threshold = UserDefaults.standard.object(forKey: "notificationThreshold") as? Int ?? 1

        let payload: [String: Any] = [
            "device_token": deviceToken,
            "device_id": deviceId,
            "environment": environment,
            "threshold": threshold
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await performRequest(request, session: session)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse(statusCode: 0)
        }
        guard http.statusCode == 200 || http.statusCode == 201 else {
            throw NetworkError.invalidResponse(statusCode: http.statusCode)
        }
    }

    // MARK: - unsubscribeAPNs
    func unsubscribeAPNs(deviceToken: String) async throws {
        let url = baseURL.appendingPathComponent("push/apns/unsubscribe")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = ["device_token": deviceToken]
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await performRequest(request, session: session)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse(statusCode: 0)
        }
        guard http.statusCode == 200 || http.statusCode == 201 else {
            throw NetworkError.invalidResponse(statusCode: http.statusCode)
        }
    }

    // MARK: - fetchSensorData
    func fetchSensorData() async throws -> Data {
        let url = baseURL.appendingPathComponent("api/inverter-data")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let delegate = RedirectCapturingDelegate()
        let delegateSession = makeSessionWithDelegate(delegate)

        let (data, response) = try await performRequest(request, session: delegateSession)

        // Detect session expiry
        if let destination = delegate.finalURL, destination.path.hasPrefix("/login") {
            throw NetworkError.sessionExpired
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NetworkError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return data
    }

    // MARK: - Private helpers

    private func performRequest(
        _ request: URLRequest,
        session: URLSession
    ) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw NetworkError.networkError(error)
        }
    }

    private func makeSessionWithDelegate(_ delegate: URLSessionTaskDelegate) -> URLSession {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    private func formEncoded(_ params: [String: String]) -> String {
        params.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }

    private func postSessionExpiredNotification() {
        NotificationCenter.default.post(name: Notification.Name("sessionExpired"), object: nil)
    }

    // MARK: - getBiometricToken
    func getBiometricToken() async throws -> String {
        let url = baseURL.appendingPathComponent("auth/biometric/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await performRequest(request, session: session)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NetworkError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let json = try? JSONDecoder().decode([String: String].self, from: data),
              let token = json["token"] else {
            throw NetworkError.decodingError(NSError(domain: "BiometricToken", code: 0))
        }
        return token
    }

    // MARK: - biometricLogin
    func biometricLogin(username: String, biometricToken: String) async throws {
        let url = baseURL.appendingPathComponent("auth/biometric/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["username": username, "biometric_token": biometricToken]
        request.httpBody = try JSONEncoder().encode(payload)

        let delegate = RedirectCapturingDelegate()
        let delegateSession = makeSessionWithDelegate(delegate)
        let (_, response) = try await performRequest(request, session: delegateSession)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse(statusCode: 0)
        }
        guard http.statusCode == 200 else {
            throw NetworkError.unauthorized
        }
    }

    // MARK: - Cookie persistence

    /// Serializza tutti i cookie di sessione Flask e li salva nel Keychain.
    func persistSessionCookies(to keychain: KeychainStoreProtocol) {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) else { return }
        let cookieData = cookies.compactMap { cookie -> [String: String]? in
            guard let expiresDate = cookie.expiresDate, expiresDate > Date() else { return nil }
            return [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path
            ]
        }
        guard !cookieData.isEmpty,
              let json = try? JSONEncoder().encode(cookieData),
              let jsonString = String(data: json, encoding: .utf8) else { return }
        try? keychain.save(token: jsonString, forKey: "flask_session_cookies")
    }

    /// Ripristina i cookie di sessione Flask dal Keychain in HTTPCookieStorage.
    func restoreSessionCookies(from keychain: KeychainStoreProtocol) {
        guard let jsonString = try? keychain.load(forKey: "flask_session_cookies"),
              let json = jsonString.data(using: .utf8),
              let cookieData = try? JSONDecoder().decode([[String: String]].self, from: json) else { return }

        for data in cookieData {
            guard let name = data["name"], let value = data["value"],
                  let domain = data["domain"], let path = data["path"] else { continue }
            let props: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: path
            ]
            if let cookie = HTTPCookie(properties: props) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    /// Verifica se la sessione corrente è ancora valida chiamando l'API.
    func validateSession() async -> Bool {
        do {
            _ = try await fetchDashboardData()
            return true
        } catch {
            return false
        }
    }
}