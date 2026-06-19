// Feature: native-apps-sensor-integration

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
                        SensorCardView(sensor: sensor, historyPoints: history[sensor.id] ?? [])
                    }
                }
            }

            if !powerSensors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Potenza (kW)", systemImage: "bolt.fill")
                        .font(.headline)
                    ForEach(powerSensors) { sensor in
                        SensorCardView(sensor: sensor, historyPoints: history[sensor.id] ?? [])
                    }
                }
            }

            if !upsSensors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("UPS", systemImage: "battery.75percent")
                        .font(.headline)
                    ForEach(upsSensors) { sensor in
                        SensorCardView(sensor: sensor, historyPoints: history[sensor.id] ?? [])
                    }
                }
            }

            if !generatorSensors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Generatori", systemImage: "fuelpump.fill")
                        .font(.headline)
                    ForEach(generatorSensors) { sensor in
                        SensorCardView(sensor: sensor, historyPoints: history[sensor.id] ?? [])
                    }
                }
            }
        }
    }

    private var temperatureSensors: [SensorReading] {
        sensors.filter { $0.category == .temperature }
    }

    private var powerSensors: [SensorReading] {
        sensors.filter { $0.category == .power }
    }

    private var upsSensors: [SensorReading] {
        sensors.filter { $0.category == .ups }
    }

    private var generatorSensors: [SensorReading] {
        sensors.filter { $0.category == .generator }
    }
}
