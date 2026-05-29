// Feature: native-apps-sensor-integration
// Requisiti: 3.3, 3.4

import SwiftUI

/// A card displaying a single sensor reading with its name, color-coded status badge,
/// and an embedded sparkline showing recent history (last 60 points).
/// Styled with rounded corners, subtle shadow, and system background.
struct SensorCardView: View {
    let sensor: SensorReading
    let thresholds: SensorThresholds?
    let historyPoints: [SensorHistoryPoint]

    private var status: AlertStatus {
        guard let t = thresholds else { return .normal }
        return sensor.alertStatus(thresholds: t)
    }

    /// Color based on alert status, with category-specific defaults for normal state.
    /// Temperature normal = orange, Power normal = blue. Warning = yellow, Critical = red.
    private var displayColor: Color {
        switch status {
        case .critical: return .red
        case .warning: return .yellow
        case .normal:
            return sensor.category == .power ? .blue : .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sensor.name)
                    .font(.headline)
                Spacer()
                // Status badge with value only (unit shown in section header)
                Text("\(sensor.value, specifier: "%.1f")")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(displayColor.opacity(0.2))
                    .foregroundColor(displayColor)
                    .cornerRadius(4)
            }

            if !historyPoints.isEmpty {
                SensorSparklineView(
                    historyPoints: Array(historyPoints.suffix(60)),
                    color: displayColor,
                    category: sensor.category
                )
                .frame(height: 50)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 0)
    }
}

// MARK: - Preview

#if DEBUG
struct SensorCardView_Previews: PreviewProvider {
    static var previews: some View {
        SensorCardView(
            sensor: SensorReading(
                id: "BRG TLC",
                name: "BRG TLC",
                category: .temperature,
                value: 23.5,
                unit: "°C",
                timestamp: nil
            ),
            thresholds: SensorThresholds(
                temperature: ThresholdPair(warning: 35.0, critical: 45.0),
                power: ThresholdPair(warning: 5.0, critical: 2.0)
            ),
            historyPoints: [
                SensorHistoryPoint(t: "2024-01-15T10:20:00", v: 23.1),
                SensorHistoryPoint(t: "2024-01-15T10:21:00", v: 23.3),
                SensorHistoryPoint(t: "2024-01-15T10:22:00", v: 23.5),
                SensorHistoryPoint(t: "2024-01-15T10:23:00", v: 24.0),
                SensorHistoryPoint(t: "2024-01-15T10:24:00", v: 23.8),
                SensorHistoryPoint(t: "2024-01-15T10:25:00", v: 23.6),
                SensorHistoryPoint(t: "2024-01-15T10:26:00", v: 23.9),
                SensorHistoryPoint(t: "2024-01-15T10:27:00", v: 24.2)
            ]
        )
        .padding()
    }
}
#endif
