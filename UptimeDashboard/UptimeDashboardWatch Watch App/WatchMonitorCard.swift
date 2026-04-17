import SwiftUI

struct WatchMonitorCard: View {
    let monitor: WatchMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Nome + stato finale
            HStack {
                Text(monitor.name)
                    .font(.system(.footnote, weight: .semibold))
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

            // Sonde — una per riga, con colore chiaro
            VStack(alignment: .leading, spacing: 3) {
                ProbeRow(label: "Aruba", status: monitor.k1)
                ProbeRow(label: "TIM", status: monitor.k2)
                ProbeRow(label: "ILIAD", status: monitor.k3)
                ProbeRow(label: "NodePing", status: monitor.n1)
                ProbeRow(label: "Uptime", status: monitor.u1)
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

// MARK: - ProbeRow

private struct ProbeRow: View {
    let label: String
    let status: String

    private var isUp: Bool { status == "UP" }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isUp ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(.caption2, weight: .medium))
                .foregroundColor(isUp ? .green : .red)
        }
    }
}
