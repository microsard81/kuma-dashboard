import Foundation

/// Stores user-configurable Y-axis limits for sensor sparklines.
/// Each unit type has a min and max stored in UserDefaults.
struct ChartLimitsSettings {
    static let shared = ChartLimitsSettings()

    private let defaults = UserDefaults.standard

    // Default values
    private let defaultLimits: [String: (min: Double, max: Double)] = [
        "°C": (15, 60),
        "V": (0, 250),
        "%": (0, 100),
        "min": (1, 280),
        "kW": (0, 100),
    ]

    func yMin(for unit: String) -> Double {
        let key = "chart_limit_min_\(unit)"
        let stored = defaults.object(forKey: key) as? Double
        return stored ?? (defaultLimits[unit]?.min ?? 0)
    }

    func yMax(for unit: String) -> Double {
        let key = "chart_limit_max_\(unit)"
        let stored = defaults.object(forKey: key) as? Double
        return stored ?? (defaultLimits[unit]?.max ?? 100)
    }

    func setYMin(_ value: Double, for unit: String) {
        defaults.set(value, forKey: "chart_limit_min_\(unit)")
    }

    func setYMax(_ value: Double, for unit: String) {
        defaults.set(value, forKey: "chart_limit_max_\(unit)")
    }

    func resetAll() {
        for unit in defaultLimits.keys {
            defaults.removeObject(forKey: "chart_limit_min_\(unit)")
            defaults.removeObject(forKey: "chart_limit_max_\(unit)")
        }
    }

    /// All configurable units with display names
    static let configurableUnits: [(unit: String, label: String)] = [
        ("°C", "Temperatura (°C)"),
        ("V", "Tensione (V)"),
        ("%", "Capacità (%)"),
        ("min", "Durata (min)"),
        ("kW", "Potenza (kW)"),
    ]
}
