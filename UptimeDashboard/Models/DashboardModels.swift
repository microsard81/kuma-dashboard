import Foundation
import SwiftUI

// MARK: - ProbeStatus
enum ProbeStatus: String, Decodable, Equatable, CaseIterable {
    case up = "UP"
    case down = "DOWN"
}

// MARK: - GlobalState
enum GlobalState: String, Decodable, Equatable {
    case green = "GREEN"
    case yellow = "YELLOW"
    case red = "RED"

    var color: Color {
        switch self {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }
}

// MARK: - RowColor
enum RowColor: Equatable {
    case green, yellow, red
}

// MARK: - HistoryPoint
/// Un punto dello storico. Decodifica sia il formato vecchio (intero)
/// che il nuovo formato oggetto {"s":int,"k1":int,"k2":int,"k3":int,"n1":int}.
struct HistoryPoint: Decodable, Equatable {
    let severity: Int
    /// Stato per-sonda: 0 = UP, 1 = DOWN. nil per punti vecchi senza dettaglio.
    let k1: Int?
    let k2: Int?
    let k3: Int?
    let n1: Int?
    let u1: Int?

    init(severity: Int, k1: Int? = nil, k2: Int? = nil, k3: Int? = nil, n1: Int? = nil, u1: Int? = nil) {
        self.severity = severity
        self.k1 = k1
        self.k2 = k2
        self.k3 = k3
        self.n1 = n1
        self.u1 = u1
    }

    init(from decoder: Decoder) throws {
        // Prova prima come intero (formato vecchio)
        if let container = try? decoder.singleValueContainer(),
           let intValue = try? container.decode(Int.self) {
            self.severity = intValue
            self.k1 = nil
            self.k2 = nil
            self.k3 = nil
            self.n1 = nil
            self.u1 = nil
            return
        }
        // Altrimenti come oggetto (formato nuovo)
        let container = try decoder.container(keyedBy: HistoryPointKeys.self)
        self.severity = try container.decode(Int.self, forKey: .s)
        self.k1 = try container.decodeIfPresent(Int.self, forKey: .k1)
        self.k2 = try container.decodeIfPresent(Int.self, forKey: .k2)
        self.k3 = try container.decodeIfPresent(Int.self, forKey: .k3)
        self.n1 = try container.decodeIfPresent(Int.self, forKey: .n1)
        self.u1 = try container.decodeIfPresent(Int.self, forKey: .u1)
    }

    private enum HistoryPointKeys: String, CodingKey {
        case s, k1, k2, k3, n1, u1
    }
}

// MARK: - MonitorItem
struct MonitorItem: Decodable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let k1: ProbeStatus
    let k2: ProbeStatus
    let k3: ProbeStatus
    let n1: ProbeStatus
    let u1: ProbeStatus
    let final: ProbeStatus
    let severity: Int
    let history: [HistoryPoint]
    let link: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.k1 = try container.decode(ProbeStatus.self, forKey: .k1)
        self.k2 = try container.decode(ProbeStatus.self, forKey: .k2)
        self.k3 = try container.decode(ProbeStatus.self, forKey: .k3)
        self.n1 = try container.decode(ProbeStatus.self, forKey: .n1)
        self.u1 = try container.decode(ProbeStatus.self, forKey: .u1)
        self.final = try container.decode(ProbeStatus.self, forKey: .final)
        self.severity = try container.decode(Int.self, forKey: .severity)
        self.history = try container.decode([HistoryPoint].self, forKey: .history)
        self.link = try container.decodeIfPresent(String.self, forKey: .link)
    }

    var rowColor: RowColor {
        switch severity {
        case 2: return .red
        case 1: return .yellow
        default: return .green
        }
    }

    var severityRank: Int {
        switch rowColor {
        case .red: return 2
        case .yellow: return 1
        case .green: return 0
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, k1, k2, k3, n1, u1
        case final = "final"
        case severity, history, link
    }
}

// MARK: - DashboardResponse
struct DashboardResponse: Decodable {
    let items: [MonitorItem]
    let globalState: GlobalState
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case items
        case globalState = "global_state"
        case timestamp
    }
}

// MARK: - SparklineSegment
struct SparklineSegment: Identifiable, Equatable {
    let id: Int
    let severity: Int
    let timestamp: Date?
    /// Stato per-sonda: 0 = UP, 1 = DOWN. nil per punti vecchi.
    let k1: Int?
    let k2: Int?
    let k3: Int?
    let n1: Int?
    let u1: Int?

    init(id: Int, severity: Int, timestamp: Date?, k1: Int? = nil, k2: Int? = nil, k3: Int? = nil, n1: Int? = nil, u1: Int? = nil) {
        self.id = id
        self.severity = severity
        self.timestamp = timestamp
        self.k1 = k1
        self.k2 = k2
        self.k3 = k3
        self.n1 = n1
        self.u1 = u1
    }

    var color: Color {
        switch severity {
        case 0: return Color(hex: "#34d399")
        case 1: return Color(hex: "#FFEE00")
        case 2: return Color(hex: "#f87171")
        default: return .gray
        }
    }
}

// MARK: - Color hex extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
