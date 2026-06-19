// Feature: native-apps-sensor-integration
// Requisiti: 3.1, 3.2, 3.3, 3.6

import SwiftUI

/// Displays the "Sensori Datacenter" section with sensors grouped by category.
/// Shows an error banner when sensor data is unavailable, and renders
/// SensorCardView for each sensor in temperature, power, UPS, and generator groups.
struct SensorSectionView: View {
    let sensors: [SensorReading]
    let history: [String: [SensorHistoryPoint]]
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sensori Datacenter")
                .font(.title2).bold()

            if let error = error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            if !temperatureSensors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Temperatura (°C)", systemImage: "thermometer.medium")
                        .font(.headline)
                    ForEach(temperatureSensors) { sensor in
                        SensorCardView(
                            sensor: sensor,
                            historyPoints: history[sensor.id] ?? []
                        )
                    }
                }
            }

            if !powerSensors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Potenza (kW)", systemImage: "bolt.fill")
                        .font(.headline)
                    ForEach(powerSensors) { sensor in
                        SensorCardView(
                            sensor: sensor,
                            historyPoints: history[sensor.id] ?? []
                        )
                    }
                }
            }

            if !upsSensors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("UPS", systemImage: "battery.75percent")
                        .font(.headline)
                    ForEach(upsSensors) { sensor in
                        SensorCardView(
                            sensor: sensor,
                            historyPoints: history[sensor.id] ?? []
                        )
                    }
                }
            }

            if !generatorSensors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Generatori", systemImage: "fuelpump.fill")
                        .font(.headline)
                    ForEach(generatorSensors) { sensor in
                        SensorCardView(
                            sensor: sensor,
                            historyPoints: history[sensor.id] ?? []
                        )
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var temperatureSensors: [SensorReading] {
        sensors.filter { $0.category == .temperature }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var powerSensors: [SensorReading] {
        sensors.filter { $0.category == .power }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var upsSensors: [SensorReading] {
        sensors.filter { $0.category == .ups }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var generatorSensors: [SensorReading] {
        sensors.filter { $0.category == .generator }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Preview

#if DEBUG
struct SensorSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            SensorSectionView(
                sensors: [
                    SensorReading(
                        id: "BRG TLC",
                        name: "BRG TLC",
                        category: .temperature,
                        value: 23.5,
                        unit: "°C",
                        timestamp: nil
                    ),
                    SensorReading(
                        id: "INV1",
                        name: "Inverter 1",
                        category: .power,
                        value: 8.2,
                        unit: "kW",
                        timestamp: nil
                    ),
                ],
                thresholds: SensorThresholds(
                    temperature: ThresholdPair(warning: 35.0, critical: 45.0),
                    power: ThresholdPair(warning: 5.0, critical: 2.0)
                ),
                history: [
                    "BRG TLC": [
                        SensorHistoryPoint(t: "2024-01-15T10:20:00", v: 23.1),
                        SensorHistoryPoint(t: "2024-01-15T10:21:00", v: 23.3),
                        SensorHistoryPoint(t: "2024-01-15T10:22:00", v: 23.5),
                    ],
                    "INV1": [
                        SensorHistoryPoint(t: "2024-01-15T10:20:00", v: 8.0),
                        SensorHistoryPoint(t: "2024-01-15T10:21:00", v: 8.1),
                        SensorHistoryPoint(t: "2024-01-15T10:22:00", v: 8.2),
                    ],
                ],
                error: nil
            )
            .padding()
        }
    }
}
#endif
