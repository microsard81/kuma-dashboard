import Foundation
import Combine
import WatchConnectivity

/// ViewModel che riceve i dati della dashboard dall'iPhone via WatchConnectivity
/// e può anche fare fetch diretto all'API del backend.
final class WatchDashboardViewModel: NSObject, ObservableObject {

    @Published var monitors: [WatchMonitor] = []
    @Published var globalState: String = "GREEN"
    @Published var lastUpdated: Date? = nil
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastError: String? = nil

    private var wcSession: WCSession?
    private var refreshTimer: Timer?

    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            wcSession = session
        }
    }

    /// Carica l'ultimo applicationContext ricevuto (sopravvive ai riavvii dell'app).
    func loadCachedData() {
        guard let session = wcSession else { return }
        let context = session.receivedApplicationContext
        if !context.isEmpty {
            processPayload(context)
        }
    }

    // MARK: - Direct API fetch

    /// Fetch diretto all'API del backend, senza dipendere dall'iPhone.
    func fetchFromAPI() async {
        guard let config = loadWatchConfig() else {
            await MainActor.run { lastError = "Config mancante (BACKEND_BASE_URL o WATCH_API_TOKEN)" }
            print("[Watch] Config mancante")
            return
        }

        await MainActor.run {
            isLoading = true
            lastError = nil
        }

        guard let url = URL(string: "\(config.baseURL)/api/watch-data") else {
            await MainActor.run { isLoading = false; lastError = "URL non valido" }
            return
        }

        var request = URLRequest(url: url)
        request.setValue(config.token, forHTTPHeaderField: "X-Watch-Token")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await MainActor.run { isLoading = false; lastError = "Risposta non HTTP" }
                return
            }
            print("[Watch] API status: \(http.statusCode)")
            guard http.statusCode == 200 else {
                await MainActor.run { isLoading = false; lastError = "HTTP \(http.statusCode)" }
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                await MainActor.run { isLoading = false; lastError = "JSON non valido" }
                return
            }
            processPayload(json)
            await MainActor.run { isLoading = false }
        } catch {
            print("[Watch] Fetch error: \(error.localizedDescription)")
            await MainActor.run { isLoading = false; lastError = error.localizedDescription }
        }
    }

    /// Avvia il refresh automatico ogni 60 secondi.
    func startAutoRefresh() {
        stopAutoRefresh()
        Task { await fetchFromAPI() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.fetchFromAPI() }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Config

    private struct WatchConfig {
        let baseURL: String
        let token: String
    }

    private func loadWatchConfig() -> WatchConfig? {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "BACKEND_BASE_URL") as? String,
              let token = Bundle.main.object(forInfoDictionaryKey: "WATCH_API_TOKEN") as? String,
              !url.isEmpty, !token.isEmpty else { return nil }
        return WatchConfig(baseURL: url, token: token)
    }
}

// MARK: - WCSessionDelegate

extension WatchDashboardViewModel: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = activationState == .activated
            if activationState == .activated {
                self.loadCachedData()
            }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        processPayload(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        processPayload(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        processPayload(applicationContext)
    }

    private func processPayload(_ payload: [String: Any]) {
        guard let itemsData = payload["items"] as? [[String: Any]] else { return }

        let parsed: [WatchMonitor] = itemsData.compactMap { dict in
            guard let name = dict["name"] as? String,
                  let k1 = dict["k1"] as? String,
                  let k2 = dict["k2"] as? String,
                  let k3 = dict["k3"] as? String,
                  let n1 = dict["n1"] as? String,
                  let final_ = dict["final"] as? String else { return nil }
            return WatchMonitor(
                name: name,
                k1: k1, k2: k2, k3: k3, n1: n1,
                finalStatus: final_
            )
        }

        DispatchQueue.main.async {
            self.monitors = parsed
            self.globalState = payload["global_state"] as? String ?? "GREEN"
            self.lastUpdated = Date()
        }
    }
}
