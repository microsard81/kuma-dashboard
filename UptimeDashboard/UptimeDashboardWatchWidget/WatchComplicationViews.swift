import SwiftUI
import WidgetKit

// MARK: - Widget Definition

struct UptimeDashboardWatchComplication: Widget {
    let kind = "UptimeDashboardWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchWidgetTimelineProvider()) { entry in
            WatchComplicationEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("INVA Status")
        .description("Risorse DOWN e stato globale")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
        ])
    }
}

// MARK: - Entry View (router per famiglia)

struct WatchComplicationEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchWidgetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularComplicationView(entry: entry)
        case .accessoryCorner:
            CornerComplicationView(entry: entry)
        case .accessoryInline:
            InlineComplicationView(entry: entry)
        default:
            CircularComplicationView(entry: entry)
        }
    }
}

// MARK: - Circular Complication (principale)
// Stile simile alla complicazione meteo: numero anomalie al centro,
// totale risorse in basso a sinistra, risorse DOWN in basso a destra.
// Cerchio aperto colorato in base allo stato globale.
// Se non ci sono anomalie uptime ma ci sono alert sensori, mostra quelli.

struct CircularComplicationView: View {
    let entry: WatchWidgetEntry

    private var anomalyCount: Int {
        entry.downCount + entry.mismatchCount
    }

    /// Color for sensor alert severity
    private var sensorAlertColor: Color {
        switch entry.sensorAlertSeverity {
        case "critical": return .red
        case "warning": return .yellow
        default: return .green
        }
    }

    var body: some View {
        if entry.isPlaceholder || entry.totalCount == 0 {
            // Placeholder
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14))
                    Text("INVA")
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundColor(.secondary)
            }
        } else {
            Gauge(value: Double(entry.totalCount - anomalyCount), in: 0...Double(entry.totalCount)) {
                // Non usato in questo stile
            } currentValueLabel: {
                // Se ci sono anomalie uptime, mostra quelle; altrimenti mostra alert sensori
                if anomalyCount > 0 {
                    Text("\(anomalyCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                } else if entry.sensorAlertCount > 0 {
                    VStack(spacing: 0) {
                        Text("🌡️")
                            .font(.system(size: 10))
                        Text("\(entry.sensorAlertCount)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(sensorAlertColor)
                    }
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.green)
                }
            } minimumValueLabel: {
                // Totale risorse in basso a sinistra
                Text("\(entry.totalCount)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            } maximumValueLabel: {
                // Risorse completamente DOWN in basso a destra (o alert sensori se no DOWN)
                Text("\(entry.downCount > 0 ? entry.downCount : entry.sensorAlertCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(entry.downCount > 0 ? .red : (entry.sensorAlertCount > 0 ? sensorAlertColor : .secondary))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(stateColor)
        }
    }

    private var stateColor: Color {
        switch entry.globalState {
        case "RED": return .red
        case "YELLOW": return .yellow
        default: return .green
        }
    }
}

// MARK: - Corner Complication

struct CornerComplicationView: View {
    let entry: WatchWidgetEntry

    /// Color for sensor alert severity
    private var sensorAlertColor: Color {
        switch entry.sensorAlertSeverity {
        case "critical": return .red
        case "warning": return .yellow
        default: return .green
        }
    }

    var body: some View {
        if entry.isPlaceholder {
            Text("INVA")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .widgetLabel {
                    Text("Caricamento...")
                }
        } else {
            Text("\(entry.downCount)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(stateColor)
                .widgetLabel {
                    if entry.sensorAlertCount > 0 {
                        Text("DOWN su \(entry.totalCount) | 🌡️\(entry.sensorAlertCount)")
                    } else {
                        Text("DOWN su \(entry.totalCount)")
                    }
                }
        }
    }

    private var stateColor: Color {
        switch entry.globalState {
        case "RED": return .red
        case "YELLOW": return .yellow
        default: return .green
        }
    }
}

// MARK: - Inline Complication

struct InlineComplicationView: View {
    let entry: WatchWidgetEntry

    var body: some View {
        if entry.isPlaceholder {
            Text("INVA: caricamento...")
        } else if entry.downCount > 0 {
            if entry.sensorAlertCount > 0 {
                Text("INVA: \(entry.downCount) DOWN / \(entry.totalCount) | 🌡️\(entry.sensorAlertCount)")
            } else {
                Text("INVA: \(entry.downCount) DOWN / \(entry.totalCount)")
            }
        } else if entry.mismatchCount > 0 {
            if entry.sensorAlertCount > 0 {
                Text("INVA: \(entry.mismatchCount) ⚠ / \(entry.totalCount) | 🌡️\(entry.sensorAlertCount)")
            } else {
                Text("INVA: \(entry.mismatchCount) ⚠ / \(entry.totalCount)")
            }
        } else if entry.sensorAlertCount > 0 {
            Text("INVA: OK (\(entry.totalCount)) | 🌡️\(entry.sensorAlertCount)")
        } else {
            Text("INVA: tutto OK (\(entry.totalCount))")
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Circular - GREEN", as: .accessoryCircular) {
    UptimeDashboardWatchComplication()
} timeline: {
    WatchWidgetEntry(date: Date(), globalState: "GREEN", totalCount: 12, downCount: 0, mismatchCount: 0, sensorAlertCount: 0, sensorAlertSeverity: "none", isPlaceholder: false)
}

#Preview("Circular - RED", as: .accessoryCircular) {
    UptimeDashboardWatchComplication()
} timeline: {
    WatchWidgetEntry(date: Date(), globalState: "RED", totalCount: 12, downCount: 3, mismatchCount: 1, sensorAlertCount: 2, sensorAlertSeverity: "critical", isPlaceholder: false)
}

#Preview("Circular - YELLOW", as: .accessoryCircular) {
    UptimeDashboardWatchComplication()
} timeline: {
    WatchWidgetEntry(date: Date(), globalState: "YELLOW", totalCount: 12, downCount: 0, mismatchCount: 2, sensorAlertCount: 1, sensorAlertSeverity: "warning", isPlaceholder: false)
}

#Preview("Circular - Sensor Only", as: .accessoryCircular) {
    UptimeDashboardWatchComplication()
} timeline: {
    WatchWidgetEntry(date: Date(), globalState: "GREEN", totalCount: 12, downCount: 0, mismatchCount: 0, sensorAlertCount: 3, sensorAlertSeverity: "warning", isPlaceholder: false)
}

#Preview("Corner", as: .accessoryCorner) {
    UptimeDashboardWatchComplication()
} timeline: {
    WatchWidgetEntry(date: Date(), globalState: "RED", totalCount: 12, downCount: 2, mismatchCount: 0, sensorAlertCount: 0, sensorAlertSeverity: "none", isPlaceholder: false)
}

#Preview("Corner - Sensor Alerts", as: .accessoryCorner) {
    UptimeDashboardWatchComplication()
} timeline: {
    WatchWidgetEntry(date: Date(), globalState: "GREEN", totalCount: 12, downCount: 0, mismatchCount: 0, sensorAlertCount: 2, sensorAlertSeverity: "critical", isPlaceholder: false)
}

#Preview("Inline", as: .accessoryInline) {
    UptimeDashboardWatchComplication()
} timeline: {
    WatchWidgetEntry(date: Date(), globalState: "GREEN", totalCount: 12, downCount: 0, mismatchCount: 0, sensorAlertCount: 0, sensorAlertSeverity: "none", isPlaceholder: false)
}

#Preview("Inline - Sensor Alerts", as: .accessoryInline) {
    UptimeDashboardWatchComplication()
} timeline: {
    WatchWidgetEntry(date: Date(), globalState: "GREEN", totalCount: 12, downCount: 0, mismatchCount: 0, sensorAlertCount: 2, sensorAlertSeverity: "warning", isPlaceholder: false)
}
#endif
