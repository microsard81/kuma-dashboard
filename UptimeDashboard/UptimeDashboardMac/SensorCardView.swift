// Feature: native-apps-sensor-integration

import SwiftUI

/// A card displaying a single sensor reading with its name, color-coded status badge,
/// and an embedded sparkline showing recent history (last 60 points).
struct SensorCardView: View {
    let sensor: SensorReading
    let historyPoints: [SensorHistoryPoint]
    @Environment(\.textScale) var scale

    private var displayColor: Color {
        if sensor.status == .critical { return .red }
        return sensor.category.normalColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sensor.name)
                    .font(.scaled(.body, scale: scale, weight: .semibold))
                Spacer()
                Text(sensor.displayValueWithUnit)
                    .font(.scaled(.caption, scale: scale, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(displayColor.opacity(0.2))
                    .foregroundColor(displayColor)
                    .cornerRadius(4)
            }

            let numericPoints = historyPoints.filter { $0.numericValue != nil }
            if !numericPoints.isEmpty {
                SensorSparklineView(
                    historyPoints: Array(numericPoints.suffix(60)),
                    color: displayColor,
                    category: sensor.category,
                    unit: sensor.unit
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
                numericValue: 23.5,
                unit: "°C",
                timestamp: nil
            ),
            historyPoints: [
                SensorHistoryPoint(t: "2024-01-15T10:20:00", v: 23.1),
                SensorHistoryPoint(t: "2024-01-15T10:21:00", v: 23.3),
                SensorHistoryPoint(t: "2024-01-15T10:22:00", v: 23.5),
            ]
        )
        .padding()
    }
}
#endif
