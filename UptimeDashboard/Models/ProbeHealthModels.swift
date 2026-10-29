import Foundation
import SwiftUI

// MARK: - ProbeHealthStatus
/// Stato complessivo riportato dall'endpoint /api/probe-health.
/// NB: distinto da `ProbeStatus` (UP/DOWN delle sonde dei portali in DashboardModels).
enum ProbeHealthStatus: String, Decodable, Equatable {
    case ok
    case disabled
    case error
}

// MARK: - KumaProbe
/// Una singola sonda di monitoraggio Kuma (check NodePing).
struct KumaProbe: Decodable, Identifiable, Equatable {
    /// check_id del webhook — usato come identità stabile.
    let checkId: String
    let label: String
    let isOperative: Bool
    let state: Int?
    /// Storico stato sonda per la sparkline (0 = operativa, 2 = non operativa).
    /// Popolato dalla view dal dizionario `history` della risposta.
    var history: [HistoryPoint]

    var id: String { checkId }

    enum CodingKeys: String, CodingKey {
        case checkId = "check_id"
        case label
        case isOperative = "is_operative"
        case state
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.checkId = (try? c.decode(String.self, forKey: .checkId)) ?? ""
        self.label = (try? c.decode(String.self, forKey: .label)) ?? ""
        self.isOperative = (try? c.decode(Bool.self, forKey: .isOperative)) ?? true
        self.state = try? c.decodeIfPresent(Int.self, forKey: .state)
        self.history = []
    }

    /// Init di convenienza per preview/test.
    init(checkId: String, label: String, isOperative: Bool, state: Int? = nil, history: [HistoryPoint] = []) {
        self.checkId = checkId
        self.label = label
        self.isOperative = isOperative
        self.state = state
        self.history = history
    }
}

// MARK: - ProbeHealthResponse
/// Risposta dell'endpoint /api/probe-health (già normalizzata dal backend).
struct ProbeHealthResponse: Decodable, Equatable {
    let status: ProbeHealthStatus
    let probes: [KumaProbe]
    let nonOperativeCount: Int
    let effectiveThreshold: Int?
    let downThresholdConfigured: Int?
    let lastCheck: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status, probes, error, history
        case nonOperativeCount = "non_operative_count"
        case effectiveThreshold = "effective_threshold"
        case downThresholdConfigured = "down_threshold_configured"
        case lastCheck = "last_check"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // status può mancare in casi anomali: default a .error per sicurezza.
        self.status = (try? c.decode(ProbeHealthStatus.self, forKey: .status)) ?? .error
        var decodedProbes = (try? c.decode([KumaProbe].self, forKey: .probes)) ?? []
        self.nonOperativeCount = (try? c.decode(Int.self, forKey: .nonOperativeCount)) ?? 0
        self.effectiveThreshold = try? c.decodeIfPresent(Int.self, forKey: .effectiveThreshold)
        self.downThresholdConfigured = try? c.decodeIfPresent(Int.self, forKey: .downThresholdConfigured)
        self.lastCheck = try? c.decodeIfPresent(String.self, forKey: .lastCheck)
        self.error = try? c.decodeIfPresent(String.self, forKey: .error)

        // Associa lo storico per-sonda (dizionario check_id -> [severity int]).
        let historyMap = (try? c.decode([String: [Int]].self, forKey: .history)) ?? [:]
        for i in decodedProbes.indices {
            if let raw = historyMap[decodedProbes[i].checkId] {
                decodedProbes[i].history = raw.map { HistoryPoint(severity: $0) }
            }
        }
        self.probes = decodedProbes
    }

    /// Init di convenienza per preview/test.
    init(status: ProbeHealthStatus, probes: [KumaProbe], nonOperativeCount: Int = 0,
         effectiveThreshold: Int? = nil, downThresholdConfigured: Int? = nil,
         lastCheck: String? = nil, error: String? = nil) {
        self.status = status
        self.probes = probes
        self.nonOperativeCount = nonOperativeCount
        self.effectiveThreshold = effectiveThreshold
        self.downThresholdConfigured = downThresholdConfigured
        self.lastCheck = lastCheck
        self.error = error
    }

    /// True se ci sono dati sonde da mostrare.
    var hasData: Bool { status == .ok && !probes.isEmpty }
}
