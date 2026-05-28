import Foundation
import SwiftUI

// MARK: - SensorCategory
enum SensorCategory: String, Codable, Equatable {
    case temperature
    case power
}

// MARK: - AlertStatus
enum AlertStatus: String, Codable, Equatable {
    case normal
    case warning
    case critical

    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

// MARK: - SensorReading
struct SensorReading: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let category: SensorCategory
    let value: Double
    let unit: String
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case id, name, category, value, unit, timestamp
    }
}

// MARK: - SensorThresholds
struct SensorThresholds: Codable, Equatable {
    let temperature: ThresholdPair
    let power: ThresholdPair
}

struct ThresholdPair: Codable, Equatable {
    let warning: Double
    let critical: Double
}

// MARK: - SensorHistoryPoint
struct SensorHistoryPoint: Codable, Equatable {
    let t: String   // ISO 8601 timestamp
    let v: Double   // sensor value
}

// MARK: - SensorAlerts
struct SensorAlerts: Codable, Equatable {
    let warningCount: Int
    let criticalCount: Int

    enum CodingKeys: String, CodingKey {
        case warningCount = "warning_count"
        case criticalCount = "critical_count"
    }

    var totalCount: Int { warningCount + criticalCount }
    var hasAlerts: Bool { totalCount > 0 }
    var hasCritical: Bool { criticalCount > 0 }
}

// MARK: - Alert Status Computation (client-side, for per-sensor coloring)
extension SensorReading {
    func alertStatus(thresholds: SensorThresholds) -> AlertStatus {
        switch category {
        case .temperature:
            if value > thresholds.temperature.critical { return .critical }
            if value > thresholds.temperature.warning { return .warning }
        case .power:
            if value < thresholds.power.critical { return .critical }
            if value < thresholds.power.warning { return .warning }
        }
        return .normal
    }
}
