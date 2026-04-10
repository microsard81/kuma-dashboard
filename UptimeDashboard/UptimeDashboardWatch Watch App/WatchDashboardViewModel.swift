import Foundation
import Combine
import WatchConnectivity

/// ViewModel che riceve i dati della dashboard dall'iPhone via WatchConnectivity.
final class WatchDashboardViewModel: NSObject, ObservableObject {

    @Published var monitors: [WatchMonitor] = []
    @Published var globalState: String = "GREEN"
    @Published var lastUpdated: Date? = nil
    @Published var isConnected: Bool = false

    private var wcSession: WCSession?

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

    /// Richiede un aggiornamento all'iPhone.
    func requestRefresh() {
        guard let session = wcSession, session.isReachable else { return }
        session.sendMessage(["action": "refresh"], replyHandler: nil)
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

    /// Riceve i dati inviati dall'iPhone con transferUserInfo o sendMessage.
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
