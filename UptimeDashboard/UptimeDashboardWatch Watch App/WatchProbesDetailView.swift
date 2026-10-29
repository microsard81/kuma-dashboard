import SwiftUI

/// Dettaglio stato sonde Kuma per watchOS — lista con stato operativo.
struct WatchProbesDetailView: View {
    @EnvironmentObject var viewModel: WatchDashboardViewModel

    private var probes: [WatchProbe] { viewModel.sortedProbes }

    var body: some View {
        List {
            ForEach(probes) { probe in
                HStack {
                    Image(systemName: probe.isOperative ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.caption2)
                        .foregroundColor(probe.isOperative ? .green : .red)
                    Text(probe.label)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(probe.isOperative ? "OK" : "KO")
                        .font(.caption2)
                        .foregroundColor(probe.isOperative ? .green : .red)
                }
            }
            if probes.isEmpty {
                Text("Nessuna sonda")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Sonde")
        .refreshable {
            await viewModel.fetchFromAPI()
        }
    }
}
