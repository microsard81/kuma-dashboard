import Foundation

/// Modello leggero per un monitor visualizzato sull'Apple Watch.
struct WatchMonitor: Identifiable {
    let id = UUID()
    let name: String
    let k1: String   // "UP" o "DOWN"
    let k2: String
    let k3: String
    let n1: String
    let finalStatus: String

    var isDown: Bool { finalStatus == "DOWN" }
    var isMismatch: Bool {
        !isDown && Set([k1, k2, k3, n1]).count > 1
    }
}
