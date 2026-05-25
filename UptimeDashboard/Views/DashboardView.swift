// Feature: ios-native-app
// Requisiti: 3.2, 3.3, 3.5, 4.1, 4.2, 4.3, 5.1, 6.1, 6.2, 7.1, 11.1, 11.2

import SwiftUI
import UserNotifications

// MARK: - DashboardView

struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel

    @State private var showLogoutAlert = false
    @State private var showSettings = false

    init(network: NetworkClientProtocol) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(network: network))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isStale { staleBanner }

                List {
                    let downItems = viewModel.filteredItems.filter { $0.rowColor == .red }
                    let mismatchItems = viewModel.filteredItems.filter { $0.rowColor == .yellow }
                    let upItems = viewModel.filteredItems.filter { $0.rowColor == .green }
                    let allUp = downItems.isEmpty && mismatchItems.isEmpty

                    if !downItems.isEmpty {
                        Section {
                            ForEach(downItems) { item in
                                MonitorRowView(item: item, openURL: openURL)
                                    .listRowBackground(rowBackground(for: item.rowColor))
                            }
                        } header: {
                            Label("DOWN", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(DeviceAdaptive.sectionHeaderFont)
                        }
                    }

                    if !mismatchItems.isEmpty {
                        Section {
                            ForEach(mismatchItems) { item in
                                MonitorRowView(item: item, openURL: openURL)
                                    .listRowBackground(rowBackground(for: item.rowColor))
                            }
                        } header: {
                            Label("Mismatch", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(DeviceAdaptive.sectionHeaderFont)
                        }
                    }

                    if !upItems.isEmpty {
                        if allUp {
                            // Tutto UP — lista piatta senza header
                            ForEach(upItems) { item in
                                MonitorRowView(item: item, openURL: openURL)
                                    .listRowBackground(rowBackground(for: item.rowColor))
                            }
                        } else {
                            Section {
                                ForEach(upItems) { item in
                                    MonitorRowView(item: item, openURL: openURL)
                                        .listRowBackground(rowBackground(for: item.rowColor))
                                }
                            } header: {
                                Label("UP", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(DeviceAdaptive.sectionHeaderFont)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await viewModel.refresh() }
            }
            .background(dashboardBackground.ignoresSafeArea())
            .navigationTitle("INVA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ledBadgeView
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Pulsante "Solo DOWN" visibile solo se ci sono risorse DOWN
                    if viewModel.downCount > 0 {
                        Toggle(isOn: $viewModel.isOnlyDownFilter) {
                            Label("Solo DOWN", systemImage: viewModel.isOnlyDownFilter
                                  ? "exclamationmark.triangle.fill"
                                  : "exclamationmark.triangle")
                        }
                        .toggleStyle(.button)
                        .tint(.red)
                    }

                    Button { showSettings = true } label: {
                        Label("Impostazioni", systemImage: "gear")
                    }
                    .accessibilityLabel("Impostazioni")

                    Button { showLogoutAlert = true } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityLabel("Logout")
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
        .onChange(of: viewModel.downCount) { newCount in
            if newCount == 0 {
                viewModel.isOnlyDownFilter = false
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settingsVM)
        }
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

    private var ledBadgeView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.ledColor)
                .frame(width: 12, height: 12)
                .shadow(color: viewModel.ledColor.opacity(0.6), radius: 3)

            if viewModel.redCount > 0 {
                Text("\(viewModel.redCount)")
                    .font(.body.bold().monospacedDigit())
                    .foregroundColor(.red)
                    .fixedSize()
            }

            if viewModel.mismatchCount > 0 {
                Text("\(viewModel.mismatchCount)")
                    .font(.body.bold().monospacedDigit())
                    .foregroundColor(.yellow)
                    .fixedSize()
            }
        }
        .padding(.horizontal, viewModel.downCount > 0 ? 10 : 6)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func rowBackground(for color: RowColor) -> Color {
        switch color {
        case .red:    return Color.red.opacity(0.12)
        case .yellow: return Color.yellow.opacity(0.10)
        case .green:  return Color.clear
        }
    }
}

// MARK: - MonitorRowView

private struct MonitorRowView: View {
    let item: MonitorItem
    let openURL: OpenURLAction

    @EnvironmentObject private var settingsVM: SettingsViewModel
    @State private var selectedSegment: SparklineSegment? = nil

    private var selectionLabel: String? {
        guard let seg = selectedSegment, let ts = seg.timestamp else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it-IT")
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: ts)
        let status: String
        switch seg.severity {
        case 0: status = "UP"
        case 1: status = "Mismatch"
        case 2: status = "DOWN"
        default: status = "?"
        }
        return "\(time) · \(status)"
    }

    /// Durante lo scrubbing su un campione mismatch, restituisce lo stato per-sonda
    /// dal campione storico. nil se non in scrubbing o se il campione non ha dati per-sonda.
    private func probeOverride(for probe: KeyPath<SparklineSegment, Int?>) -> ProbeStatus? {
        guard let seg = selectedSegment,
              seg.severity == 1, // solo mismatch
              let val = seg[keyPath: probe] else { return nil }
        return val == 0 ? .down : .up
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let urlString = item.link, let url = URL(string: urlString) {
                    Button { openURL(url) } label: {
                        Text(item.name).font(DeviceAdaptive.monitorNameFont).foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(item.name).font(DeviceAdaptive.monitorNameFont)
                }
                Spacer()
                Text(item.final.rawValue)
                    .font(DeviceAdaptive.statusBadgeFont).foregroundColor(.white)
                    .padding(.horizontal, DeviceAdaptive.badgeHPadding)
                    .padding(.vertical, DeviceAdaptive.badgeVPadding)
                    .background(item.final == .down ? Color.red : Color.green)
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                ProbeIndicator(label: "Aruba", status: probeOverride(for: \.k1) ?? item.k1)
                ProbeIndicator(label: "TIM", status: probeOverride(for: \.k2) ?? item.k2)
                ProbeIndicator(label: "ILIAD", status: probeOverride(for: \.k3) ?? item.k3)
                ProbeIndicator(label: "NodePing", status: probeOverride(for: \.n1) ?? item.n1)
                ProbeIndicator(label: "Uptime", status: probeOverride(for: \.u1) ?? item.u1)
                Spacer()
                if let label = selectionLabel {
                    Text(label)
                        .font(DeviceAdaptive.selectionLabelFont)
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: selectedSegment?.id)

            SparklineView(history: item.history, selectedSegment: $selectedSegment, hapticEnabled: settingsVM.hapticEnabled)
                .frame(height: DeviceAdaptive.sparklineHeight)
        }
        .padding(.vertical, DeviceAdaptive.rowVerticalPadding)
    }
}

// MARK: - ProbeIndicator

private struct ProbeIndicator: View {
    let label: String
    let status: ProbeStatus

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(status == .up ? Color.green : Color.red)
                .frame(width: DeviceAdaptive.probeDotSize, height: DeviceAdaptive.probeDotSize)
                .animation(.easeInOut(duration: 0.3), value: status)
            Text(label).font(DeviceAdaptive.probeLabelFont).foregroundColor(.secondary)
        }
    }
}
