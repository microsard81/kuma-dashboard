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

// MARK: - MonitorItem
struct MonitorItem: Decodable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let k1: ProbeStatus
    let k2: ProbeStatus
    let k3: ProbeStatus
    let n1: ProbeStatus
    let final: ProbeStatus
    let severity: Int
    let history: [Int]
    let link: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.k1 = try container.decode(ProbeStatus.self, forKey: .k1)
        self.k2 = try container.decode(ProbeStatus.self, forKey: .k2)
        self.k3 = try container.decode(ProbeStatus.self, forKey: .k3)
        self.n1 = try container.decode(ProbeStatus.self, forKey: .n1)
        self.final = try container.decode(ProbeStatus.self, forKey: .final)
        self.severity = try container.decode(Int.self, forKey: .severity)
        self.history = try container.decode([Int].self, forKey: .history)
        self.link = try container.decodeIfPresent(String.self, forKey: .link)
    }

    var rowColor: RowColor {
        if final == .down { return .red }
        let probes: Set<ProbeStatus> = [k1, k2, k3, n1]
        if probes.count > 1 { return .yellow }
        return .green
    }

    var severityRank: Int {
        switch rowColor {
        case .red: return 2
        case .yellow: return 1
        case .green: return 0
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, k1, k2, k3, n1
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
struct SparklineSegment: Identifiable {
    let id: Int
    let severity: Int
    let timestamp: Date?

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
