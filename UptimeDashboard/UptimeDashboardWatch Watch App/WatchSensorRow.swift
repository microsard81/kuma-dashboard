import SwiftUI

struct WatchSensorRow: View {
    let sensor: SensorReading
    let thresholds: SensorThresholds?

    private var status: AlertStatus {
        guard let t = thresholds else { return .normal }
        return sensor.alertStatus(thresholds: t)
    }

    var body: some View {
        HStack {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(sensor.name)
                .font(.caption2)
            Spacer()
            Text("\(sensor.value, specifier: "%.1f") \(sensor.unit)")
                .font(.caption2)
                .monospacedDigit()
        }
    }
}
