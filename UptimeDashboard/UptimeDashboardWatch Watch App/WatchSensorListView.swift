import SwiftUI

struct WatchSensorListView: View {
    let sensors: [SensorReading]
    let thresholds: SensorThresholds?
    let error: String?

    var body: some View {
        if let error = error {
            Text(error)
                .font(.caption2)
                .foregroundColor(.orange)
        }

        if !temperatureSensors.isEmpty {
            Section("Temperatura") {
                ForEach(temperatureSensors) { sensor in
                    WatchSensorRow(sensor: sensor, thresholds: thresholds)
                }
            }
        }

        if !powerSensors.isEmpty {
            Section("Potenza") {
                ForEach(powerSensors) { sensor in
                    WatchSensorRow(sensor: sensor, thresholds: thresholds)
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
}
