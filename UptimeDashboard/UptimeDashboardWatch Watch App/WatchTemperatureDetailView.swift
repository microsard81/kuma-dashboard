import SwiftUI

struct WatchTemperatureDetailView: View {
    @EnvironmentObject var viewModel: WatchDashboardViewModel

    private var sensors: [SensorReading] {
        viewModel.sensors.filter { $0.category == .temperature }
    }

    var body: some View {
        List {
            ForEach(sensors) { sensor in
                WatchSensorRow(sensor: sensor, thresholds: viewModel.sensorThresholds)
            }
        }
        .navigationTitle("Temperatura")
    }
}
