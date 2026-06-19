import SwiftUI

struct WatchSensorListView: View {
    let sensors: [SensorReading]
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
                    WatchSensorRow(sensor: sensor)
                }
            }
        }

        if !powerSensors.isEmpty {
            Section("Potenza") {
                ForEach(powerSensors) { sensor in
                    WatchSensorRow(sensor: sensor)
                }
            }
        }

        if !upsSensors.isEmpty {
            Section("UPS") {
                ForEach(upsSensors) { sensor in
                    WatchSensorRow(sensor: sensor)
                }
            }
        }

        if !generatorSensors.isEmpty {
            Section("Generatori") {
                ForEach(generatorSensors) { sensor in
                    WatchSensorRow(sensor: sensor)
                }
            }
        }
    }

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
