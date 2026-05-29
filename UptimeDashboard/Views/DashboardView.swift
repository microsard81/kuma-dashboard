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
    @State private var unreadNotifications = NotificationStore.shared.unreadCount
    @State private var pinnedItems: [PinnedItem] = PinnedStore.shared.loadAll()
    @State private var isReorderingPinned = false
    @State private var draggingPinnedItem: PinnedItem? = nil
    @State private var selectedPinnedItem: PinnedItem? = nil
    @State private var sectionOrder: [String] = UserDefaults.standard.stringArray(forKey: "ios_section_order") ?? ["portali", "temperatura", "potenza"]
    @State private var isReorderingSections = false
    @State private var selectedSection: String? = nil

    init(network: NetworkClientProtocol) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(network: network))
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

                ScrollView {
                    VStack(spacing: 16) {
                        if isReorderingSections {
                            // Reorder mode: List with drag handles
                            HStack {
                                Spacer()
                                Button {
                                    UserDefaults.standard.set(sectionOrder, forKey: "ios_section_order")
                                    withAnimation { isReorderingSections = false }
                                } label: {
                                    Text("Fine")
                                        .font(.caption.bold())
                                        .foregroundColor(.blue)
                                }
                            }

                            List {
                                ForEach(sectionOrder, id: \.self) { section in
                                    HStack {
                                        Image(systemName: sectionIcon(section))
                                            .foregroundColor(sectionColor(section))
                                        Text(sectionTitle(section))
                                            .font(.headline)
                                    }
                                }
                                .onMove { from, to in
                                    sectionOrder.move(fromOffsets: from, toOffset: to)
                                }
                            }
                            .listStyle(.plain)
                            .environment(\.editMode, .constant(.active))
                            .frame(height: 180)
                        } else {
                            // Normal mode: tap to navigate, long press to reorder
                            ForEach(sectionOrder, id: \.self) { section in
                                switch section {
                                case "portali":
                                    MacroAreaCard(
                                        title: "Portali",
                                        icon: "globe",
                                        statusColor: portalsColor,
                                        subtitle: portalsSubtitle,
                                        alertCount: viewModel.redCount + viewModel.mismatchCount
                                    )
                                    .onTapGesture { selectedSection = "portali" }
                                    .onLongPressGesture(minimumDuration: 0.5) {
                                        withAnimation { isReorderingSections = true }
                                    }
                                case "temperatura":
                                    if !viewModel.temperatureSensors.isEmpty {
                                        MacroAreaCard(
                                            title: "Temperatura",
                                            icon: "thermometer.medium",
                                            statusColor: temperatureStatusColor,
                                            subtitle: temperatureSubtitle,
                                            alertCount: temperatureAlertCount
                                        )
                                        .onTapGesture { selectedSection = "temperatura" }
                                        .onLongPressGesture(minimumDuration: 0.5) {
                                            withAnimation { isReorderingSections = true }
                                        }
                                    }
                                case "potenza":
                                    if !viewModel.powerSensors.isEmpty {
                                        MacroAreaCard(
                                            title: "Potenza",
                                            icon: "bolt.fill",
                                            statusColor: powerStatusColor,
                                            subtitle: powerSubtitle,
                                            alertCount: powerAlertCount
                                        )
                                        .onTapGesture { selectedSection = "potenza" }
                                        .onLongPressGesture(minimumDuration: 0.5) {
                                            withAnimation { isReorderingSections = true }
                                        }
                                    }
                                default:
                                    EmptyView()
                                }
                            }

                            // Hidden NavigationLinks for programmatic navigation
                            NavigationLink(
                                destination: PortalsDetailView(viewModel: viewModel).environmentObject(settingsVM),
                                isActive: Binding(get: { selectedSection == "portali" }, set: { if !$0 { selectedSection = nil } })
                            ) { EmptyView() }.hidden()
                            NavigationLink(
                                destination: TemperatureDetailView(viewModel: viewModel),
                                isActive: Binding(get: { selectedSection == "temperatura" }, set: { if !$0 { selectedSection = nil } })
                            ) { EmptyView() }.hidden()
                            NavigationLink(
                                destination: PowerDetailView(viewModel: viewModel),
                                isActive: Binding(get: { selectedSection == "potenza" }, set: { if !$0 { selectedSection = nil } })
                            ) { EmptyView() }.hidden()
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
                        }

                        // Pinned items (square cards)
                        if !pinnedItems.isEmpty {
                            Divider()
                                .padding(.vertical, 4)

                            // Header with title + Fine button
                            HStack {
                                Text("In evidenza")
                                    .font(.headline)
                                Spacer()
                                if isReorderingPinned {
                                    Button {
                                        PinnedStore.shared.reorder(pinnedItems)
                                        withAnimation { isReorderingPinned = false }
                                    } label: {
                                        Text("Fine")
                                            .font(.caption.bold())
                                            .foregroundColor(.blue)
                                    }
                                }
                            }

                            // Remove all (centered, only in reorder mode)
                            if isReorderingPinned {
                                Button(role: .destructive) {
                                    PinnedStore.shared.unpinAll()
                                    withAnimation {
                                        pinnedItems = []
                                        isReorderingPinned = false
                                    }
                                } label: {
                                    Label("Rimuovi tutti", systemImage: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                            }

                            if isReorderingPinned {
                                // Reorder mode: cards with remove badge + drag
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(pinnedItems) { item in
                                        ZStack(alignment: .topLeading) {
                                            PinnedCardView(item: item, viewModel: viewModel)
                                                .aspectRatio(1, contentMode: .fit)
                                                .opacity(draggingPinnedItem?.id == item.id ? 0.5 : 1)
                                            Button {
                                                PinnedStore.shared.unpin(id: item.id)
                                                withAnimation { pinnedItems = PinnedStore.shared.loadAll() }
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .font(.system(size: 18))
                                                    .foregroundColor(.red)
                                                    .background(Circle().fill(Color.white).frame(width: 16, height: 16))
                                            }
                                            .offset(x: -6, y: -6)
                                        }
                                        .onDrag {
                                            draggingPinnedItem = item
                                            return NSItemProvider(object: item.id as NSString)
                                        }
                                        .onDrop(of: [.text], delegate: PinnedReorderDropDelegate(
                                            item: item,
                                            items: $pinnedItems,
                                            draggingItem: $draggingPinnedItem
                                        ))
                                    }
                                }
                            } else {
                                // Normal mode: tap to navigate, long press to enter reorder
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(pinnedItems) { item in
                                        PinnedCardView(item: item, viewModel: viewModel)
                                            .aspectRatio(1, contentMode: .fit)
                                            .onTapGesture {
                                                selectedPinnedItem = item
                                            }
                                            .onLongPressGesture(minimumDuration: 0.5) {
                                                withAnimation { isReorderingPinned = true }
                                            }
                                    }
                                }
                                .background(
                                    NavigationLink(
                                        destination: Group {
                                            if let item = selectedPinnedItem {
                                                pinnedDestination(for: item)
                                            }
                                        },
                                        isActive: Binding(
                                            get: { selectedPinnedItem != nil },
                                            set: { if !$0 { selectedPinnedItem = nil } }
                                        )
                                    ) { EmptyView() }
                                        .hidden()
                                )
                            }
                        }
                    }
                    .padding()
                }
                .refreshable { await viewModel.refresh() }

                // MARK: - Footer actions (fixed at bottom, centered)
                Divider()
                HStack(spacing: 32) {
                    NavigationLink {
                        NotificationHistoryView()
                    } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")
                                    .font(.title3)
                                if unreadNotifications > 0 {
                                    Text("\(unreadNotifications)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(3)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                        .offset(x: 8, y: -4)
                                }
                            }
                            Text("Notifiche")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            unreadNotifications = 0
                        }
                    })

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
            unreadNotifications = NotificationStore.shared.unreadCount
            pinnedItems = PinnedStore.shared.loadAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinnedItemsChanged)) { _ in
            withAnimation { pinnedItems = PinnedStore.shared.loadAll() }
        }
        .onDisappear { viewModel.stopAutoRefresh() }
        .onChange(of: viewModel.lastUpdated) { _ in
            unreadNotifications = NotificationStore.shared.unreadCount
        }
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

    // MARK: - Section Helpers

    private func sectionIcon(_ section: String) -> String {
        switch section {
        case "portali": return "globe"
        case "temperatura": return "thermometer.medium"
        case "potenza": return "bolt.fill"
        default: return "questionmark"
        }
    }

    private func sectionColor(_ section: String) -> Color {
        switch section {
        case "portali": return portalsColor
        case "temperatura": return temperatureStatusColor
        case "potenza": return powerStatusColor
        default: return .gray
        }
    }

    private func sectionTitle(_ section: String) -> String {
        switch section {
        case "portali": return "Portali"
        case "temperatura": return "Temperatura"
        case "potenza": return "Potenza"
        default: return section
        }
    }

    // MARK: - Pinned Helpers

    private func iconForType(_ type: PinnedItem.PinnedType) -> String {
        switch type {
        case .portale: return "globe"
        case .temperatura: return "thermometer.medium"
        case .potenza: return "bolt.fill"
        }
    }

    private func colorForType(_ type: PinnedItem.PinnedType) -> Color {
        switch type {
        case .portale: return .green
        case .temperatura: return .orange
        case .potenza: return .blue
        }
    }

    // MARK: - Pinned Destination

    @ViewBuilder
    private func pinnedDestination(for item: PinnedItem) -> some View {
        switch item.type {
        case .portale:
            PortalsDetailView(viewModel: viewModel)
                .environmentObject(settingsVM)
        case .temperatura:
            TemperatureDetailView(viewModel: viewModel)
        case .potenza:
            PowerDetailView(viewModel: viewModel)
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
