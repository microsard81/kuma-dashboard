import SwiftUI

struct WatchTemperatureDetailView: View {
    @EnvironmentObject var viewModel: WatchDashboardViewModel

    private var sensors: [SensorReading] {
        let all = viewModel.sensors.filter { $0.category == .temperature }
        return all.sorted {
            let rank0 = $0.status == .critical ? 1 : 0
            let rank1 = $1.status == .critical ? 1 : 0
            if rank0 != rank1 { return rank0 > rank1 }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            ForEach(sensors) { sensor in
                WatchSensorRow(sensor: sensor)
            }
        }
        .navigationTitle("Temperatura")
        .refreshable {
            await viewModel.fetchFromAPI()
        }
    }
}
