import Foundation
import SwiftUI

// MARK: - SensorCategory
enum SensorCategory: String, Codable, Equatable {
    case temperature
    case power
    case ups
    case generator
    case other
}

// MARK: - AlertStatus
enum AlertStatus: String, Codable, Equatable {
    case normal
    case critical

    var color: Color {
        switch self {
        case .normal: return .green
        case .critical: return .red
        }
    }
}

// MARK: - SensorReading
struct SensorReading: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let category: SensorCategory
    let unit: String
    let timestamp: String?
    let site: String?
    let room: String?
    let type: String?
    let description: String?
    let status: AlertStatus

    let numericValue: Double?
    let stringValue: String?

    var displayValue: String {
        if let v = numericValue {
            if v == v.rounded() && v >= 100 { return "\(Int(v))" }
            return String(format: "%.1f", v)
        }
        return stringValue ?? "—"
    }

    var displayValueWithUnit: String {
        let v = displayValue
        if v == "—" { return v }
        return unit.isEmpty ? v : "\(v) \(unit)"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, category, unit, timestamp, site, room, type, description, status, value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = (try? container.decode(SensorCategory.self, forKey: .category)) ?? .other
        unit = (try? container.decode(String.self, forKey: .unit)) ?? ""
        timestamp = try? container.decode(String.self, forKey: .timestamp)
        site = try? container.decode(String.self, forKey: .site)
        room = try? container.decode(String.self, forKey: .room)
        type = try? container.decode(String.self, forKey: .type)
        description = try? container.decode(String.self, forKey: .description)
        status = (try? container.decode(AlertStatus.self, forKey: .status)) ?? .normal

        if let v = try? container.decode(Double.self, forKey: .value) {
            numericValue = v
            stringValue = nil
        } else if let v = try? container.decode(String.self, forKey: .value) {
            numericValue = nil
            stringValue = v
        } else {
            numericValue = nil
            stringValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(unit, forKey: .unit)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(site, forKey: .site)
        try container.encodeIfPresent(room, forKey: .room)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(status, forKey: .status)
        if let v = numericValue {
            try container.encode(v, forKey: .value)
        } else if let v = stringValue {
            try container.encode(v, forKey: .value)
        }
    }

    init(id: String, name: String, category: SensorCategory, numericValue: Double?, stringValue: String? = nil, unit: String, timestamp: String?, status: AlertStatus = .normal, site: String? = nil, room: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.numericValue = numericValue
        self.stringValue = stringValue
        self.unit = unit
        self.timestamp = timestamp
        self.status = status
        self.site = site
        self.room = room
        self.type = nil
        self.description = nil
    }

    var alertStatus: AlertStatus { status }
}

// MARK: - SensorHistoryPoint
struct SensorHistoryPoint: Codable, Equatable {
    let t: String
    let numericValue: Double?
    let stringValue: String?

    var displayValue: String {
        if let v = numericValue { return String(format: "%.1f", v) }
        return stringValue ?? "—"
    }

    enum CodingKeys: String, CodingKey {
        case t, v
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        t = try container.decode(String.self, forKey: .t)
        if let v = try? container.decode(Double.self, forKey: .v) {
            numericValue = v
            stringValue = nil
        } else if let v = try? container.decode(String.self, forKey: .v) {
            numericValue = nil
            stringValue = v
        } else {
            numericValue = nil
            stringValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(t, forKey: .t)
        if let v = numericValue {
            try container.encode(v, forKey: .v)
        } else if let v = stringValue {
            try container.encode(v, forKey: .v)
        }
    }

    init(t: String, v: Double) {
        self.t = t
        self.numericValue = v
        self.stringValue = nil
    }
}

// MARK: - SensorAlerts
struct SensorAlerts: Codable, Equatable {
    let criticalCount: Int

    enum CodingKeys: String, CodingKey {
        case criticalCount = "critical_count"
    }

    var hasAlerts: Bool { criticalCount > 0 }
}

// MARK: - Category Display Helpers
extension SensorCategory {
    var displayName: String {
        switch self {
        case .temperature: return "Temperatura"
        case .power: return "Potenza"
        case .ups: return "UPS"
        case .generator: return "Generatori"
        case .other: return "Altro"
        }
    }

    var icon: String {
        switch self {
        case .temperature: return "thermometer.medium"
        case .power: return "bolt.fill"
        case .ups: return "battery.75percent"
        case .generator: return "fuelpump.fill"
        case .other: return "sensor.fill"
        }
    }

    var normalColor: Color {
        switch self {
        case .temperature: return .orange
        case .power: return .blue
        case .ups: return .purple
        case .generator: return .orange
        case .other: return .gray
        }
    }
}
