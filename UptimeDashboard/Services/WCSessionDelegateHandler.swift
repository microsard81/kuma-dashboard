import WatchConnectivity

/// Delegate WCSession per il lato iPhone.
/// Gestisce l'attivazione e le richieste dal watch.
final class WCSessionDelegateHandler: NSObject, WCSessionDelegate {
    static let shared = WCSessionDelegateHandler()

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[WCSession] Activation error: \(error.localizedDescription)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
