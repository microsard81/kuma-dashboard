import SwiftUI

struct WatchTemperatureDetailView: View {
    @EnvironmentObject var viewModel: WatchDashboardViewModel

    private var sensors: [SensorReading] {
        let all = viewModel.sensors.filter { $0.category == .temperature }
        guard let t = viewModel.sensorThresholds else {
            return all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        // Ordina per gravità, poi alfabetico dentro ogni gruppo
        return all.sorted {
            let rank0 = severityRank($0.alertStatus(thresholds: t))
            let rank1 = severityRank($1.alertStatus(thresholds: t))
            if rank0 != rank1 { return rank0 > rank1 }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func severityRank(_ status: AlertStatus) -> Int {
        switch status {
        case .critical: return 2
        case .warning: return 1
        case .normal: return 0
        }
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
