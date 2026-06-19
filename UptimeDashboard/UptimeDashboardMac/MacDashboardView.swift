import SwiftUI

// MARK: - Color hex extension for macOS
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Dashboard Section

enum DashboardSection: String, CaseIterable, Identifiable {
    case portali
    case temperatura
    case potenza
    case ups
    case generatori

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .portali: return "Portali"
        case .temperatura: return "Temperatura"
        case .potenza: return "Potenza"
        case .ups: return "UPS"
        case .generatori: return "Generatori"
        }
    }

    var shortName: String {
        switch self {
        case .portali: return "Portali"
        case .temperatura: return "Temp"
        case .potenza: return "Potenza"
        case .ups: return "UPS"
        case .generatori: return "GE"
        }
    }

    var icon: String {
        switch self {
        case .portali: return "globe"
        case .temperatura: return "thermometer.medium"
        case .potenza: return "bolt.fill"
        case .ups: return "battery.75percent"
        case .generatori: return "fuelpump.fill"
        }
    }
}

// MARK: - Main Dashboard View

struct MacDashboardView: View {
    @EnvironmentObject var viewModel: MacAppViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.textScale) var scale
    @State private var selectedSection: DashboardSection? = nil
    @State private var showOnlyProblems = false
    @State private var showNotificationHistory = false
    @State private var unreadNotifications = NotificationStore.shared.unreadCount
    @State private var manualPortalOrder: [String] = UserDefaults.standard.stringArray(forKey: "mac_manual_order_portali") ?? []
    @State private var manualSensorOrder: [String: [String]] = {
        var result: [String: [String]] = [:]
        for key in ["temperatura", "potenza", "ups", "generatori"] {
            result[key] = UserDefaults.standard.stringArray(forKey: "mac_manual_order_\(key)") ?? []
        }
        return result
    }()
    @State private var isReorderingPortals = false
    @State private var isReorderingSensors = false

    private var filteredMonitors: [MacMonitor] {
        var sorted: [MacMonitor]
        switch viewModel.sortOrder {
        case "alphabetical":
            sorted = viewModel.monitors.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "globalState":
            sorted = viewModel.monitors.sorted { globalRank($0) > globalRank($1) }
        default:
            sorted = viewModel.monitors.sorted { rank($0) > rank($1) }
        }
        if showOnlyProblems {
            return sorted.filter { $0.isDown || $0.isMismatch }
        }
        return sorted
    }

    private var problemCount: Int {
        viewModel.monitors.filter { $0.isDown || $0.isMismatch }.count
    }

    private var dashboardBackground: Color {
        colorScheme == .dark ? Color(hex: "#141c2b") : Color(.windowBackgroundColor)
    }

    // MARK: - Sensor status colors

    private var temperatureStatusColor: Color {
        if viewModel.temperatureSensors.contains(where: { $0.status == .critical }) { return .red }
        return .orange
    }

    private var powerStatusColor: Color {
        if viewModel.powerSensors.contains(where: { $0.status == .critical }) { return .red }
        return .blue
    }

    private var upsStatusColor: Color {
        if viewModel.upsSensors.contains(where: { $0.status == .critical }) { return .red }
        return .purple
    }

    private var generatorStatusColor: Color {
        if viewModel.generatorSensors.contains(where: { $0.status == .critical }) { return .red }
        return .orange
    }

    private func sectionStatusColor(for section: DashboardSection) -> Color {
        switch section {
        case .portali: return ledColor
        case .temperatura: return temperatureStatusColor
        case .potenza: return powerStatusColor
        case .ups: return upsStatusColor
        case .generatori: return generatorStatusColor
        }
    }

    private var ledColor: Color {
        switch viewModel.globalState {
        case "RED": return .red
        case "YELLOW": return .yellow
        default: return .green
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbarView
            Divider()

            if showNotificationHistory {
                MacNotificationInlineView()
                    .onAppear {
                        NotificationStore.shared.markAllAsRead()
                        unreadNotifications = 0
                    }
            } else {
                NavigationSplitView {
                    sidebarContent
                        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
                } detail: {
                    detailContent
                }
            }
        }
        .background(dashboardBackground)
        .preferredColorScheme(.dark)
        .onChange(of: problemCount) { newCount in
            if newCount == 0 {
                showOnlyProblems = false
            }
        }
        .task {
            await NotificationStore.shared.syncFromServer()
            unreadNotifications = NotificationStore.shared.unreadCount
        }
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack {
            Text("Dashboard INVA")
                .font(.scaled(.headline, scale: scale))

            Spacer()

            if let date = viewModel.lastUpdated {
                Text("Aggiornato: \(date, style: .time)")
                    .font(.scaled(.caption, scale: scale))
                    .foregroundColor(.secondary)
            }

            Button {
                Task { await viewModel.fetchDashboard() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Aggiorna")

            Button {
                showNotificationHistory.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: showNotificationHistory ? "bell.fill" : "bell")
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                    if unreadNotifications > 0 && !showNotificationHistory {
                        Text("\(unreadNotifications)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(2)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 4, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Notifiche")

            Button {
                viewModel.logout()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Logout")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selectedSection) {
            // Panoramica button (deselects any section)
            Section {
                Button {
                    selectedSection = nil
                } label: {
                    Label {
                        Text("Panoramica")
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                            .foregroundColor(.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .opacity(selectedSection == nil ? 0.5 : 1.0)
            }
            .padding(.top, 12)

            Divider()

            ForEach(DashboardSection.allCases) { section in
                Label {
                    HStack {
                        Text(section.displayName)
                        Spacer()
                        let badge = sidebarBadge(for: section)
                        if let badge = badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(sectionStatusColor(for: section), in: Capsule())
                        } else {
                            Circle()
                                .fill(sectionStatusColor(for: section))
                                .frame(width: 8, height: 8)
                        }
                    }
                } icon: {
                    Image(systemName: section.icon)
                        .foregroundColor(sectionStatusColor(for: section))
                }
                .tag(section)
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarBadge(for section: DashboardSection) -> String? {
        switch section {
        case .portali:
            let down = viewModel.monitors.filter { $0.isDown }.count
            let mismatch = viewModel.monitors.filter { $0.isMismatch }.count
            if down > 0 { return "\(down)" }
            if mismatch > 0 { return "\(mismatch)" }
            return nil
        case .temperatura:
            let c = viewModel.temperatureSensors.filter { $0.status == .critical }.count
            return c > 0 ? "\(c)" : nil
        case .potenza:
            let c = viewModel.powerSensors.filter { $0.status == .critical }.count
            return c > 0 ? "\(c)" : nil
        case .ups:
            let c = viewModel.upsSensors.filter { $0.status == .critical }.count
            return c > 0 ? "\(c)" : nil
        case .generatori:
            let c = viewModel.generatorSensors.filter { $0.status == .critical }.count
            return c > 0 ? "\(c)" : nil
        }
    }

    // MARK: - Detail

    private var detailContent: some View {
        Group {
            if let section = selectedSection {
                sectionDetailContent(for: section)
            } else {
                overviewGrid
            }
        }
    }

    // MARK: - Overview Grid

    private var overviewGrid: some View {
        GeometryReader { geo in
            let columns = adaptiveColumns(for: geo.size.width)
            ScrollView {
                VStack(spacing: 20) {
                    // Section cards
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(DashboardSection.allCases) { section in
                            OverviewCard(
                                section: section,
                                statusText: overviewStatusText(for: section),
                                statusColor: sectionStatusColor(for: section)
                            ) {
                                selectedSection = section
                            }
                        }
                    }

                    // Pinned items section (below main cards)
                    if !pinnedItems.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("In evidenza")
                                    .font(.scaled(.subheadline, scale: scale, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 4)

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(pinnedItems) { item in
                                    MacPinnedCardView(item: item, viewModel: viewModel) {
                                        selectedSection = sectionForPinnedItem(item)
                                    }
                                    .contextMenu {
                                        Button("Rimuovi da In evidenza") {
                                            MacPinnedStore.shared.unpin(id: item.id)
                                            refreshPinned()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(minHeight: geo.size.height)
            }
        }
        .onAppear { refreshPinned() }
    }

    @State private var pinnedItems: [MacPinnedItem] = MacPinnedStore.shared.loadAll()

    private func refreshPinned() {
        pinnedItems = MacPinnedStore.shared.loadAll()
    }

    private func sectionForPinnedItem(_ item: MacPinnedItem) -> DashboardSection {
        switch item.type {
        case .portale: return .portali
        case .temperatura: return .temperatura
        case .potenza: return .potenza
        case .ups: return .ups
        case .generatore: return .generatori
        }
    }

    private func adaptiveColumns(for width: CGFloat) -> [GridItem] {
        let minCardWidth: CGFloat = 140
        let count = max(1, Int(width / (minCardWidth + 16)))
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
    }

    private func overviewStatusText(for section: DashboardSection) -> String {
        switch section {
        case .portali:
            let total = viewModel.monitors.count
            let down = viewModel.monitors.filter { $0.isDown }.count
            let mismatch = viewModel.monitors.filter { $0.isMismatch }.count
            if down > 0 { return "\(down)/\(total) DOWN" }
            if mismatch > 0 { return "\(mismatch)/\(total) Mismatch" }
            return "OK (\(total))"
        case .temperatura:
            let sensors = viewModel.temperatureSensors
            let critical = sensors.filter { $0.status == .critical }.count
            if critical > 0 { return "\(critical)/\(sensors.count) Critical" }
            return "OK (\(sensors.count))"
        case .potenza:
            let sensors = viewModel.powerSensors
            let critical = sensors.filter { $0.status == .critical }.count
            if critical > 0 { return "\(critical)/\(sensors.count) Critical" }
            return "OK (\(sensors.count))"
        case .ups:
            let sensors = viewModel.upsSensors
            let critical = sensors.filter { $0.status == .critical }.count
            if critical > 0 { return "\(critical)/\(sensors.count) Critical" }
            return "OK (\(sensors.count))"
        case .generatori:
            let sensors = viewModel.generatorSensors
            let critical = sensors.filter { $0.status == .critical }.count
            if critical > 0 { return "\(critical)/\(sensors.count) Critical" }
            return "OK (\(sensors.count))"
        }
    }

    // MARK: - Section Detail Content

    @ViewBuilder
    private func sectionDetailContent(for section: DashboardSection) -> some View {
        switch section {
        case .portali:
            portalsDetail
        case .temperatura:
            sensorDetail(
                sensors: sortedSensors(viewModel.sensors.filter { $0.category == .temperature }),
                title: "Temperatura (°C)",
                icon: "thermometer.medium",
                color: temperatureStatusColor
            )
        case .potenza:
            sensorDetail(
                sensors: sortedSensors(viewModel.sensors.filter { $0.category == .power }),
                title: "Potenza (kW)",
                icon: "bolt.fill",
                color: powerStatusColor
            )
        case .ups:
            sensorDetail(
                sensors: sortedSensors(viewModel.sensors.filter { $0.category == .ups }),
                title: "UPS",
                icon: "battery.75percent",
                color: upsStatusColor
            )
        case .generatori:
            sensorDetail(
                sensors: sortedSensors(viewModel.sensors.filter { $0.category == .generator }),
                title: "Generatori",
                icon: "fuelpump.fill",
                color: generatorStatusColor
            )
        }
    }

    // MARK: - Portals Detail

    private var portalsDetail: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(ledColor)
                Text("Portali")
                    .font(.scaled(.headline, scale: scale))
                Spacer()
                if problemCount > 0 {
                    Toggle(isOn: $showOnlyProblems) {
                        Label("Solo problemi", systemImage: showOnlyProblems
                              ? "exclamationmark.triangle.fill"
                              : "exclamationmark.triangle")
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
                Button {
                    withAnimation { isReorderingPortals.toggle() }
                } label: {
                    Image(systemName: isReorderingPortals ? "checkmark.circle.fill" : "arrow.up.arrow.down")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help(isReorderingPortals ? "Termina riordino" : "Riordina manualmente")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(ledColor.opacity(0.05))

            Divider()

            if isReorderingPortals {
                portalReorderList
            } else {
                portalNormalList
            }
        }
    }

    private var portalNormalList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let monitors = orderedMonitors
                let downItems = monitors.filter { $0.isDown }
                let mismatchItems = monitors.filter { $0.isMismatch }
                let upItems = monitors.filter { !$0.isDown && !$0.isMismatch }
                let allUp = downItems.isEmpty && mismatchItems.isEmpty

                if !downItems.isEmpty {
                    SectionHeader(title: "DOWN", icon: "xmark.circle.fill", color: .red)
                    ForEach(downItems) { monitor in
                        MacMonitorRow(monitor: monitor)
                            .background(Color.red.opacity(0.12))
                            .contextMenu { pinContextMenu(for: monitor.name, type: .portale) }
                    }
                }

                if !mismatchItems.isEmpty {
                    SectionHeader(title: "Mismatch", icon: "exclamationmark.triangle.fill", color: .yellow)
                    ForEach(mismatchItems) { monitor in
                        MacMonitorRow(monitor: monitor)
                            .background(Color.yellow.opacity(0.10))
                            .contextMenu { pinContextMenu(for: monitor.name, type: .portale) }
                    }
                }

                if !upItems.isEmpty {
                    if !allUp {
                        SectionHeader(title: "UP", icon: "checkmark.circle.fill", color: .green)
                    }
                    ForEach(upItems) { monitor in
                        MacMonitorRow(monitor: monitor)
                            .contextMenu { pinContextMenu(for: monitor.name, type: .portale) }
                    }
                }
            }
        }
    }

    private var portalReorderList: some View {
        List {
            ForEach(reorderableMonitors, id: \.name) { monitor in
                HStack {
                    Image(systemName: "line.3.horizontal")
                        .foregroundColor(.secondary)
                    Text(monitor.name)
                        .font(.scaled(.body, scale: scale))
                    Spacer()
                    Text(monitor.finalStatus)
                        .font(.scaled(.caption, scale: scale, weight: .bold))
                        .foregroundColor(monitor.isDown ? .red : (monitor.isMismatch ? .yellow : .green))
                }
            }
            .onMove { from, to in
                var items = reorderableMonitors.map(\.name)
                items.move(fromOffsets: from, toOffset: to)
                manualPortalOrder = items
                UserDefaults.standard.set(items, forKey: "mac_manual_order_portali")
            }
        }
        .listStyle(.plain)
    }

    private var orderedMonitors: [MacMonitor] {
        if !manualPortalOrder.isEmpty {
            // Manual order: respect saved order, new items at end
            var ordered: [MacMonitor] = []
            for name in manualPortalOrder {
                if let m = filteredMonitors.first(where: { $0.name == name }) {
                    ordered.append(m)
                }
            }
            for m in filteredMonitors where !manualPortalOrder.contains(m.name) {
                ordered.append(m)
            }
            return ordered
        }
        return filteredMonitors
    }

    private var reorderableMonitors: [MacMonitor] {
        // All monitors in current manual order (or default sorted)
        if !manualPortalOrder.isEmpty {
            var ordered: [MacMonitor] = []
            for name in manualPortalOrder {
                if let m = viewModel.monitors.first(where: { $0.name == name }) {
                    ordered.append(m)
                }
            }
            for m in viewModel.monitors where !manualPortalOrder.contains(m.name) {
                ordered.append(m)
            }
            return ordered
        }
        return viewModel.monitors
    }

    // MARK: - Sensor Detail (generic)

    private func sensorDetail(sensors: [SensorReading], title: String, icon: String, color: Color) -> some View {
        let sectionKey = sectionKeyForTitle(title)
        let manualOrder = manualSensorOrder[sectionKey] ?? []
        let orderedSensors = applyManualOrder(sensors: sensors, order: manualOrder)

        return VStack(spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.scaled(.headline, scale: scale))
                Spacer()
                Button {
                    withAnimation { isReorderingSensors.toggle() }
                } label: {
                    Image(systemName: isReorderingSensors ? "checkmark.circle.fill" : "arrow.up.arrow.down")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help(isReorderingSensors ? "Termina riordino" : "Riordina manualmente")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(color.opacity(0.05))

            Divider()

            if sensors.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Nessun sensore disponibile")
                        .font(.scaled(.subheadline, scale: scale))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isReorderingSensors {
                List {
                    ForEach(orderedSensors) { sensor in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                            Text(sensor.name)
                                .font(.scaled(.body, scale: scale))
                            Spacer()
                            Text(sensor.displayValueWithUnit)
                                .font(.scaled(.caption, scale: scale, weight: .bold))
                                .foregroundColor(sensor.status == .critical ? .red : .secondary)
                        }
                    }
                    .onMove { from, to in
                        var items = orderedSensors.map(\.id)
                        items.move(fromOffsets: from, toOffset: to)
                        manualSensorOrder[sectionKey] = items
                        UserDefaults.standard.set(items, forKey: "mac_manual_order_\(sectionKey)")
                    }
                }
                .listStyle(.plain)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(orderedSensors) { sensor in
                            SensorCardView(
                                sensor: sensor,
                                historyPoints: viewModel.sensorHistory[sensor.id] ?? []
                            )
                            .padding(.horizontal, 16)
                            .contextMenu { pinContextMenuForSensor(sensor) }
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private func sectionKeyForTitle(_ title: String) -> String {
        if title.contains("Temperatura") { return "temperatura" }
        if title.contains("Potenza") { return "potenza" }
        if title.contains("UPS") { return "ups" }
        if title.contains("Generatori") { return "generatori" }
        return "other"
    }

    private func applyManualOrder(sensors: [SensorReading], order: [String]) -> [SensorReading] {
        guard !order.isEmpty else { return sensors }
        var ordered: [SensorReading] = []
        for id in order {
            if let s = sensors.first(where: { $0.id == id }) {
                ordered.append(s)
            }
        }
        for s in sensors where !order.contains(s.id) {
            ordered.append(s)
        }
        return ordered
    }

    // MARK: - Pin Context Menu

    @ViewBuilder
    private func pinContextMenu(for id: String, type: MacPinnedItem.PinnedType) -> some View {
        if MacPinnedStore.shared.isPinned(id: id) {
            Button {
                MacPinnedStore.shared.unpin(id: id)
                refreshPinned()
            } label: {
                Label("Rimuovi da In evidenza", systemImage: "pin.slash")
            }
        } else {
            Button {
                MacPinnedStore.shared.pin(id: id, type: type)
                refreshPinned()
            } label: {
                Label("Aggiungi a In evidenza", systemImage: "pin")
            }
        }
    }

    @ViewBuilder
    private func pinContextMenuForSensor(_ sensor: SensorReading) -> some View {
        let type: MacPinnedItem.PinnedType = {
            switch sensor.category {
            case .temperature: return .temperatura
            case .power: return .potenza
            case .ups: return .ups
            case .generator: return .generatore
            case .other: return .potenza
            }
        }()
        pinContextMenu(for: sensor.id, type: type)
    }

    // MARK: - Helpers

    private func sortedSensors(_ sensors: [SensorReading]) -> [SensorReading] {
        let sortOrder = viewModel.sortOrder
        if sortOrder == "alphabetical" {
            return sensors.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        let critical = sensors.filter { $0.status == .critical }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let normal = sensors.filter { $0.status == .normal }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return critical + normal
    }

    private func rank(_ m: MacMonitor) -> Int {
        if m.isDown { return 2 }
        if m.isMismatch { return 1 }
        return 0
    }

    private func globalRank(_ m: MacMonitor) -> Int {
        if m.isDown { return 2 }
        if m.isMismatch { return 1 }
        return 0
    }
}

// MARK: - Overview Card

private struct OverviewCard: View {
    let section: DashboardSection
    let statusText: String
    let statusColor: Color
    let action: () -> Void
    @Environment(\.textScale) var scale

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: section.icon)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(statusColor)

                Text(section.shortName)
                    .font(.scaled(.body, scale: scale, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(statusText)
                    .font(.scaled(.subheadline, scale: scale, weight: .bold))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: "#1e2a3a"))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color
    @Environment(\.textScale) var scale

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.scaled(.caption, scale: scale, weight: .bold))
                .foregroundColor(color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(color.opacity(0.05))
    }
}

// MARK: - Monitor Row

private struct MacMonitorRow: View {
    let monitor: MacMonitor
    @Environment(\.openURL) var openURL
    @Environment(\.textScale) var scale
    @State private var selectionLabel: String? = nil
    @State private var hoveredSegment: MacSparklineSegment? = nil

    private func probeOverride(probe: String) -> String? {
        guard let seg = hoveredSegment, seg.severity == 1 else { return nil }
        let val: Int?
        switch probe {
        case "k1": val = seg.k1
        case "k2": val = seg.k2
        case "k3": val = seg.k3
        case "n1": val = seg.n1
        case "u1": val = seg.u1
        default: val = nil
        }
        guard let v = val else { return nil }
        return v == 0 ? "DOWN" : "UP"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let urlString = monitor.link, let url = URL(string: urlString) {
                    Button { openURL(url) } label: {
                        Text(monitor.name).font(.scaled(.body, scale: scale, weight: .semibold)).foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(monitor.name).font(.scaled(.body, scale: scale, weight: .semibold))
                }
                Spacer()
                Text(monitor.finalStatus)
                    .font(.scaled(.caption, scale: scale, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor)
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                ProbeIndicator(label: "Aruba", status: probeOverride(probe: "k1") ?? monitor.k1)
                ProbeIndicator(label: "TIM", status: probeOverride(probe: "k2") ?? monitor.k2)
                ProbeIndicator(label: "ILIAD", status: probeOverride(probe: "k3") ?? monitor.k3)
                ProbeIndicator(label: "NodePing", status: probeOverride(probe: "n1") ?? monitor.n1)
                ProbeIndicator(label: "Uptime", status: probeOverride(probe: "u1") ?? monitor.u1)
                Spacer()
                if let label = selectionLabel {
                    Text(label)
                        .font(.scaled(.caption2, scale: scale, weight: .bold))
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: selectionLabel)

            MacSparklineView(history: monitor.history, selectionLabel: $selectionLabel, hoveredSegment: $hoveredSegment)
                .frame(height: 28)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)

        Divider().padding(.leading, 16)
    }

    private var badgeColor: Color {
        monitor.isDown ? .red : (monitor.isMismatch ? .yellow : .green)
    }
}

// MARK: - Probe Indicator

private struct ProbeIndicator: View {
    let label: String
    let status: String
    @Environment(\.textScale) var scale

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(status == "UP" ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.scaled(.caption, scale: scale))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Sparkline con tooltip (macOS)

private struct MacSparklineView: View {
    let history: [[String: Any]]
    @Binding var selectionLabel: String?
    @Binding var hoveredSegment: MacSparklineSegment?

    private let samplingInterval: TimeInterval = 60

    private var segments: [MacSparklineSegment] {
        let pts = points
        let now = Date()
        return pts.enumerated().map { offset, point in
            let secsAgo = TimeInterval(pts.count - 1 - offset) * samplingInterval
            let timestamp = now.addingTimeInterval(-secsAgo)
            return MacSparklineSegment(id: offset, severity: point.severity,
                                        k1: point.k1, k2: point.k2, k3: point.k3, n1: point.n1, u1: point.u1,
                                        timestamp: timestamp)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let count = segments.count
            let bw = barWidth(totalWidth: geo.size.width, count: count)
            let cellWidth = bw + 1.0

            HStack(alignment: .bottom, spacing: 1) {
                ForEach(segments) { seg in
                    Rectangle()
                        .fill(colorFor(seg.severity))
                        .frame(width: bw)
                }
            }
            .frame(maxHeight: .infinity)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let idx = Int(location.x / cellWidth)
                    if idx >= 0, idx < count {
                        let seg = segments[idx]
                        hoveredSegment = seg
                        let formatter = DateFormatter()
                        formatter.locale = Locale(identifier: "it-IT")
                        formatter.dateFormat = "HH:mm"
                        selectionLabel = formatter.string(from: seg.timestamp)
                    }
                case .ended:
                    selectionLabel = nil
                    hoveredSegment = nil
                }
            }
        }
    }

    private struct HistoryPoint {
        let severity: Int
        let k1: Int?
        let k2: Int?
        let k3: Int?
        let n1: Int?
        let u1: Int?
    }

    private var points: [HistoryPoint] {
        history.compactMap { dict in
            if let s = dict["s"] as? Int {
                return HistoryPoint(severity: s,
                                    k1: dict["k1"] as? Int,
                                    k2: dict["k2"] as? Int,
                                    k3: dict["k3"] as? Int,
                                    n1: dict["n1"] as? Int,
                                    u1: dict["u1"] as? Int)
            }
            return nil
        }
    }

    private func colorFor(_ severity: Int) -> Color {
        switch severity {
        case 0: return Color(hex: "#34d399")
        case 1: return Color(hex: "#FFEE00")
        case 2: return Color(hex: "#f87171")
        default: return .gray
        }
    }

    private func barWidth(totalWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let spacing = CGFloat(count - 1) * 1.0
        return max(1, (totalWidth - spacing) / CGFloat(count))
    }
}

private struct MacSparklineSegment: Identifiable {
    let id: Int
    let severity: Int
    let k1: Int?
    let k2: Int?
    let k3: Int?
    let n1: Int?
    let u1: Int?
    let timestamp: Date
}

// MARK: - Mac Pinned Card View

private struct MacPinnedCardView: View {
    let item: MacPinnedItem
    @ObservedObject var viewModel: MacAppViewModel
    @Environment(\.textScale) var scale
    var onDoubleTap: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(cardColor)

            Text(displayName)
                .font(.scaled(.caption, scale: scale, weight: .bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)

            Text(statusText)
                .font(.scaled(.subheadline, scale: scale, weight: .bold))
                .foregroundColor(cardColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "#1e2a3a"))
        )
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
    }

    private var displayName: String {
        item.id.replacingOccurrences(of: "INVA - ", with: "")
    }

    private var iconName: String {
        switch item.type {
        case .portale: return "globe"
        case .temperatura: return "thermometer.medium"
        case .potenza: return "bolt.fill"
        case .ups: return "battery.75percent"
        case .generatore: return "fuelpump.fill"
        }
    }

    private var sectionForItem: DashboardSection {
        switch item.type {
        case .portale: return .portali
        case .temperatura: return .temperatura
        case .potenza: return .potenza
        case .ups: return .ups
        case .generatore: return .generatori
        }
    }

    private var cardColor: Color {
        switch item.type {
        case .portale:
            if let monitor = viewModel.monitors.first(where: { $0.name == item.id }) {
                if monitor.isDown { return .red }
                if monitor.isMismatch { return .yellow }
            }
            return .green
        case .temperatura:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                if sensor.status == .critical { return .red }
            }
            return .orange
        case .potenza:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                if sensor.status == .critical { return .red }
            }
            return .blue
        case .ups:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                if sensor.status == .critical { return .red }
            }
            return .purple
        case .generatore:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                if sensor.status == .critical { return .red }
            }
            return .orange
        }
    }

    private var statusText: String {
        switch item.type {
        case .portale:
            if let monitor = viewModel.monitors.first(where: { $0.name == item.id }) {
                return monitor.finalStatus
            }
            return "—"
        case .temperatura, .potenza, .ups, .generatore:
            if let sensor = viewModel.sensors.first(where: { $0.id == item.id }) {
                return sensor.displayValueWithUnit
            }
            return "—"
        }
    }
}

// MARK: - Notification Inline View (macOS — in-window)

private struct MacNotificationInlineView: View {
    @State private var notifications: [NotificationRecord] = []
    @State private var isLoading = false
    @Environment(\.textScale) var scale

    private let baseURL = "https://kuma-dashboard.sundata.cloud"

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && notifications.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Caricamento...")
                        .font(.scaled(.subheadline, scale: scale))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if notifications.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Nessuna notifica")
                        .font(.scaled(.title3, scale: scale))
                        .foregroundColor(.secondary)
                    Text("Gli eventi appariranno qui")
                        .font(.scaled(.subheadline, scale: scale))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(notifications) { notif in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(notif.title)
                                .font(.scaled(.subheadline, scale: scale).bold())
                            Spacer()
                            Text(formatDate(notif.date))
                                .font(.scaled(.caption, scale: scale))
                                .foregroundColor(.secondary)
                        }
                        if !notif.body.isEmpty {
                            Text(notif.body)
                                .font(.scaled(.body, scale: scale))
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .task {
            await fetchServerEvents()
        }
    }

    private func fetchServerEvents() async {
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/api/events?limit=200") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONDecoder().decode(MacEventsResponse.self, from: data) else {
            return
        }

        notifications = json.events
            .filter { $0.type != "global" }
            .map { event in
            NotificationRecord(
                title: event.title,
                body: event.body,
                date: event.date,
                isRead: false,
                requestId: event.id
            )
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Ieri' HH:mm"
        } else {
            formatter.dateFormat = "dd/MM HH:mm"
        }
        return formatter.string(from: date)
    }
}
