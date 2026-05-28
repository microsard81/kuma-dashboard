// Feature: ios-native-app

import SwiftUI

// MARK: - MonitorRowView

struct MonitorRowView: View {
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
              seg.severity == 1,
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

struct ProbeIndicator: View {
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
