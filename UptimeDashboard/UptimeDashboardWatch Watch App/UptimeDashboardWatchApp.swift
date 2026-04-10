import SwiftUI

@main
struct UptimeDashboardWatchApp: App {
    @StateObject private var viewModel = WatchDashboardViewModel()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environmentObject(viewModel)
                .onAppear { viewModel.startAutoRefresh() }
                .onDisappear { viewModel.stopAutoRefresh() }
        }
    }
}
