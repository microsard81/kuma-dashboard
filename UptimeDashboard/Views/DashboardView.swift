// Feature: ios-native-app
// Requisiti: 3.2, 3.3, 3.5, 4.1, 4.2, 4.3, 5.1, 6.1, 6.2, 7.1, 11.1, 11.2

import SwiftUI
import UserNotifications

// MARK: - DashboardView

struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel

    @State private var showLogoutAlert = false
    @State private var isReorderingSections = false
    @State private var sectionOrder: [String] = []

    private let sectionOrderKey = "dashboard_section_order"
    private let defaultOrder = ["portali", "temperatura", "potenza"]

    init(network: NetworkClientProtocol) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(network: network))
    }

    private var displayOrder: [String] {
        if isReorderingSections { return sectionOrder }
        let saved = UserDefaults.standard.stringArray(forKey: sectionOrderKey) ?? []
        return saved.isEmpty ? defaultOrder : saved
    }

    // MARK: - Computed states

    /// Worst alert status among temperature sensors.
    /// Normal = orange (category default).
    private var temperatureStatusColor: Color {
        guard let thresholds = viewModel.sensorThresholds else { return .orange }
        let statuses = viewModel.temperatureSensors.map { $0.alertStatus(thresholds: thresholds) }
        if statuses.contains(.critical) { return .red }
        if statuses.contains(.warning) { return .yellow }
        return .orange
    }

    /// Worst alert status among power sensors.
    /// Normal = blue (category default).
    private var powerStatusColor: Color {
        guard let thresholds = viewModel.sensorThresholds else { return .blue }
        let statuses = viewModel.powerSensors.map { $0.alertStatus(thresholds: thresholds) }
        if statuses.contains(.critical) { return .red }
        if statuses.contains(.warning) { return .yellow }
        return .blue
    }

    /// Global state color for portals.
    private var portalsColor: Color {
        viewModel.globalState.color
    }

    /// Number of temperature sensors in alert state.
    private var temperatureAlertCount: Int {
        guard let t = viewModel.sensorThresholds else { return 0 }
        return viewModel.temperatureSensors.filter { $0.alertStatus(thresholds: t) != .normal }.count
    }

    /// Number of power sensors in alert state.
    private var powerAlertCount: Int {
        guard let t = viewModel.sensorThresholds else { return 0 }
        return viewModel.powerSensors.filter { $0.alertStatus(thresholds: t) != .normal }.count
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isStale { staleBanner }

                List {
                    ForEach(displayOrder, id: \.self) { section in
                        switch section {
                        case "portali":
                            sectionPortali
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                        case "temperatura":
                            if !viewModel.temperatureSensors.isEmpty {
                                sectionTemperatura
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                            }
                        case "potenza":
                            if !viewModel.powerSensors.isEmpty {
                                sectionPotenza
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                            }
                        default:
                            EmptyView()
                        }
                    }
                    .onMove { from, to in
                        sectionOrder.move(fromOffsets: from, toOffset: to)
                    }

                    // Sensor error banner (only if no sensor data available)
                    if let error = viewModel.sensorError, viewModel.sensors.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, isReorderingSections ? .constant(.active) : .constant(.inactive))
                .refreshable { await viewModel.refresh() }

                // MARK: - Footer actions (fixed at bottom, centered)
                Divider()
                HStack(spacing: 32) {
                    NavigationLink {
                        NotificationHistoryView()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "bell")
                                .font(.title3)
                            Text("Notifiche")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }

                    NavigationLink {
                        SettingsView()
                            .environmentObject(settingsVM)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "gear")
                                .font(.title3)
                            Text("Impostazioni")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }

                    NavigationLink {
                        HelpView()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "questionmark.circle")
                                .font(.title3)
                            Text("Aiuto")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }

                    Button { showLogoutAlert = true } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.title3)
                            Text("Logout")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .background(dashboardBackground.ignoresSafeArea())
            .navigationTitle("Dashboard INVA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if isReorderingSections {
                            // Save and exit
                            UserDefaults.standard.set(sectionOrder, forKey: sectionOrderKey)
                            withAnimation { isReorderingSections = false }
                        } else {
                            // Enter reorder mode
                            sectionOrder = displayOrder
                            withAnimation { isReorderingSections = true }
                        }
                    } label: {
                        Image(systemName: isReorderingSections ? "lock.open" : "lock")
                            .foregroundColor(isReorderingSections ? .orange : .secondary)
                    }
                }
            }
            .alert("Conferma logout", isPresented: $showLogoutAlert) {
                Button("Annulla", role: .cancel) {}
                Button("Logout", role: .destructive) {
                    Task { await authViewModel.logout() }
                }
            } message: {
                Text("Sei sicuro di voler uscire?")
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            viewModel.bindSettings(settingsVM)
            viewModel.startAutoRefresh()
        }
        .onDisappear { viewModel.stopAutoRefresh() }
        .onChange(of: viewModel.downCount) { count in
            if settingsVM.badgeEnabled {
                UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
            }
        }
        .onChange(of: settingsVM.badgeEnabled) { enabled in
            if !enabled {
                UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
            }
        }
    }

    // MARK: - Section Views

    private var sectionPortali: some View {
        NavigationLink {
            PortalsDetailView(viewModel: viewModel)
                .environmentObject(settingsVM)
        } label: {
            MacroAreaCard(
                title: "Portali",
                icon: "globe",
                statusColor: portalsColor,
                subtitle: portalsSubtitle,
                alertCount: viewModel.redCount + viewModel.mismatchCount
            )
        }
        .buttonStyle(.plain)
    }

    private var sectionTemperatura: some View {
        NavigationLink {
            TemperatureDetailView(viewModel: viewModel)
        } label: {
            MacroAreaCard(
                title: "Temperatura",
                icon: "thermometer.medium",
                statusColor: temperatureStatusColor,
                subtitle: temperatureSubtitle,
                alertCount: temperatureAlertCount
            )
        }
        .buttonStyle(.plain)
    }

    private var sectionPotenza: some View {
        NavigationLink {
            PowerDetailView(viewModel: viewModel)
        } label: {
            MacroAreaCard(
                title: "Potenza",
                icon: "bolt.fill",
                statusColor: powerStatusColor,
                subtitle: powerSubtitle,
                alertCount: powerAlertCount
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subtitles

    private var portalsSubtitle: String {
        let total = viewModel.items.count
        let down = viewModel.redCount
        let mismatch = viewModel.mismatchCount
        if down > 0 { return "\(down) DOWN su \(total)" }
        if mismatch > 0 { return "\(mismatch) mismatch su \(total)" }
        return "Tutto OK (\(total))"
    }

    private var temperatureSubtitle: String {
        let count = viewModel.temperatureSensors.count
        guard let thresholds = viewModel.sensorThresholds else { return "\(count) sensori" }
        let alerts = viewModel.temperatureSensors.filter { $0.alertStatus(thresholds: thresholds) != .normal }.count
        if alerts > 0 { return "\(alerts) in allarme su \(count)" }
        return "Tutto OK (\(count))"
    }

    private var powerSubtitle: String {
        let count = viewModel.powerSensors.count
        guard let thresholds = viewModel.sensorThresholds else { return "\(count) sensori" }
        let alerts = viewModel.powerSensors.filter { $0.alertStatus(thresholds: thresholds) != .normal }.count
        if alerts > 0 { return "\(alerts) in allarme su \(count)" }
        return "Tutto OK (\(count))"
    }

    // MARK: - Subviews

    @Environment(\.colorScheme) private var colorScheme

    private var dashboardBackground: Color {
        colorScheme == .dark ? Color(hex: "#141c2b") : Color(.systemBackground)
    }

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundColor(.orange)
            Text("Dati non aggiornati").font(.subheadline).foregroundColor(.orange)
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

}

// MARK: - MacroAreaCard

private struct MacroAreaCard: View {
    let title: String
    let icon: String
    let statusColor: Color
    let subtitle: String
    var alertCount: Int = 0

    var body: some View {
        HStack(spacing: 16) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // LED badge + chevron
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: statusColor.opacity(0.6), radius: 3)
                    if alertCount > 0 {
                        Text("\(alertCount)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundColor(statusColor)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}
