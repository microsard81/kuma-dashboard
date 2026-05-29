// Feature: native-apps-sensor-integration
// Requisiti: 3.4

import SwiftUI
import Charts

/// A compact line + area sparkline for sensor history data.
/// Displays the last 60 data points using catmullRom interpolation.
/// Supports interactive tooltip on touch/hover showing value and time (HH:mm).
/// Y-axis uses fixed scale based on sensor category.
struct SensorSparklineView: View {
    let historyPoints: [SensorHistoryPoint]
    let color: Color
    var category: SensorCategory = .temperature

    @State private var selectedIndex: Int? = nil

    /// Fixed Y scale based on category
    private var yMin: Double { category == .power ? 1 : 10 }
    private var yMax: Double { category == .power ? 100 : 65 }

    /// Parsed data points with raw timestamp for tooltip display.
    private var dataPoints: [(rawTime: String, value: Double, index: Int)] {
        Array(historyPoints.suffix(60)).enumerated().map { index, point in
            let time = extractTime(from: point.t)
            return (rawTime: time, value: point.v, index: index)
        }
    }

    var body: some View {
        Chart {
            ForEach(dataPoints, id: \.index) { point in
                LineMark(
                    x: .value("Index", point.index),
                    y: .value("Valore", point.value)
                )
                .foregroundStyle(color.gradient)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Index", point.index),
                    y: .value("Valore", point.value)
                )
                .foregroundStyle(color.opacity(0.1).gradient)
                .interpolationMethod(.catmullRom)
            }

            // Selection indicator
            if let idx = selectedIndex, let point = dataPoints.first(where: { $0.index == idx }) {
                RuleMark(x: .value("Index", point.index))
                    .foregroundStyle(color.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 4) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f", point.value))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(color)
                            Text(point.rawTime.isEmpty ? "—" : point.rawTime)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yMin...yMax)
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedIndex)
        .onChange(of: selectedIndex) { _ in
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
        }
    }

    /// Extract HH:mm from a raw timestamp string
    private func extractTime(from str: String) -> String {
        // Look for T followed by HH:mm (e.g. "2026-05-29T08:37:00+00:00")
        if let tIndex = str.firstIndex(of: "T") {
            let timeStart = str.index(after: tIndex)
            let timeStr = String(str[timeStart...])
            if timeStr.count >= 5 {
                return String(timeStr.prefix(5))
            }
        }
        // Look for space followed by HH:mm (e.g. "2026-05-29 08:37:00")
        if let spaceIndex = str.firstIndex(of: " ") {
            let timeStart = str.index(after: spaceIndex)
            let timeStr = String(str[timeStart...])
            if timeStr.count >= 5 {
                return String(timeStr.prefix(5))
            }
        }
        // If the string itself looks like HH:mm or HH:mm:ss
        if str.count >= 5, str.contains(":") {
            return String(str.prefix(5))
        }
        return str
    }
}

// MARK: - Legacy convenience init (backward compatibility)
extension SensorSparklineView {
    init(points: [Double], color: Color) {
        let now = Date()
        let syntheticPoints = points.suffix(60).enumerated().map { index, value in
            let date = now.addingTimeInterval(Double(index - points.suffix(60).count) * 60)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return SensorHistoryPoint(t: formatter.string(from: date), v: value)
        }
        self.historyPoints = syntheticPoints
        self.color = color
        self.category = .temperature
    }
}

// MARK: - Preview

#if DEBUG
struct SensorSparklineView_Previews: PreviewProvider {
    static var previews: some View {
        SensorSparklineView(
            historyPoints: [
                SensorHistoryPoint(t: "2024-01-15T10:20:00+00:00", v: 23.1),
                SensorHistoryPoint(t: "2024-01-15T10:21:00+00:00", v: 23.3),
                SensorHistoryPoint(t: "2024-01-15T10:22:00+00:00", v: 23.5),
                SensorHistoryPoint(t: "2024-01-15T10:23:00+00:00", v: 24.0),
                SensorHistoryPoint(t: "2024-01-15T10:24:00+00:00", v: 23.8),
                SensorHistoryPoint(t: "2024-01-15T10:25:00+00:00", v: 23.6),
                SensorHistoryPoint(t: "2024-01-15T10:26:00+00:00", v: 23.9),
                SensorHistoryPoint(t: "2024-01-15T10:27:00+00:00", v: 24.2),
            ],
            color: .orange,
            category: .temperature
        )
        .frame(height: 50)
        .padding()
    }
}
#endif
