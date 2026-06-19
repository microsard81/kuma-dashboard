import SwiftUI

/// Generic detail view for any sensor category (UPS, Generators, etc.)
struct WatchCategoryDetailView: View {
    @EnvironmentObject var viewModel: WatchDashboardViewModel
    let category: SensorCategory

    private var sensors: [SensorReading] {
        viewModel.sensors.filter { $0.category == category }
            .sorted {
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
        .navigationTitle(category.displayName)
        .refreshable {
            await viewModel.fetchFromAPI()
        }
    }
}
