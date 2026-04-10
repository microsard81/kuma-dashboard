import SwiftUI

@main
struct UptimeDashboardWatchApp: App {
    @StateObject private var viewModel = WatchDashboardViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environmentObject(viewModel)
                .onAppear { viewModel.startAutoRefresh() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        // Refresh immediato quando l'app torna in primo piano
                        Task { await viewModel.fetchFromAPI() }
                    }
                }
        }
    }
}
