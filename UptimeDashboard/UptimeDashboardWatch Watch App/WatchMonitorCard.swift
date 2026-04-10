import SwiftUI

struct WatchMonitorCard: View {
    let monitor: WatchMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Nome + stato finale
            HStack {
                Text(monitor.name)
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .lineLimit(2)
                Spacer()
                Text(monitor.finalStatus)
                    .font(.system(.caption2, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor)
                    .clipShape(Capsule())
            }

            // Sonde
            HStack(spacing: 6) {
                ProbeChip(label: "Aruba", status: monitor.k1)
                ProbeChip(label: "TIM", status: monitor.k2)
            }
            HStack(spacing: 6) {
                ProbeChip(label: "ILIAD", status: monitor.k3)
                ProbeChip(label: "NP", status: monitor.n1)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(rowColor)
    }

    private var badgeColor: Color {
        monitor.isDown ? .red : (monitor.isMismatch ? .yellow : .green)
    }

    private var rowColor: Color {
        if monitor.isDown { return Color.red.opacity(0.15) }
        if monitor.isMismatch { return Color.yellow.opacity(0.12) }
        return Color.clear
    }
}

// MARK: - ProbeChip

private struct ProbeChip: View {
    let label: String
    let status: String

    private var isUp: Bool { status == "UP" }

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(isUp ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}
