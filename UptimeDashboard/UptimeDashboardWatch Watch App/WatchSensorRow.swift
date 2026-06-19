import SwiftUI

struct WatchSensorRow: View {
    let sensor: SensorReading

    var body: some View {
        HStack {
            Circle()
                .fill(sensor.status == .critical ? Color.red : sensor.category.normalColor)
                .frame(width: 8, height: 8)
            Text(sensor.name)
                .font(.caption2)
            Spacer()
            Text(sensor.displayValueWithUnit)
                .font(.caption2)
                .monospacedDigit()
        }
    }
}
