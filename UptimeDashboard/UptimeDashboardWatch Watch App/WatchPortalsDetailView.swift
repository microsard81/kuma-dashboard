import SwiftUI

struct WatchPortalsDetailView: View {
    @EnvironmentObject var viewModel: WatchDashboardViewModel

    var body: some View {
        let downItems = viewModel.monitors.filter { $0.isDown }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let mismatchItems = viewModel.monitors.filter { $0.isMismatch }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let upItems = viewModel.monitors.filter { !$0.isDown && !$0.isMismatch }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let allUp = downItems.isEmpty && mismatchItems.isEmpty

        List {
            if !downItems.isEmpty {
                Section {
                    ForEach(downItems) { WatchMonitorCard(monitor: $0) }
                } header: {
                    Label("DOWN", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }

            if !mismatchItems.isEmpty {
                Section {
                    ForEach(mismatchItems) { WatchMonitorCard(monitor: $0) }
                } header: {
                    Label("Mismatch", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                }
            }

            if !upItems.isEmpty {
                if allUp {
                    ForEach(upItems) { WatchMonitorCard(monitor: $0) }
                } else {
                    Section {
                        ForEach(upItems) { WatchMonitorCard(monitor: $0) }
                    } header: {
                        Label("UP", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .navigationTitle("Portali")
        .refreshable {
            await viewModel.fetchFromAPI()
        }
    }
}
