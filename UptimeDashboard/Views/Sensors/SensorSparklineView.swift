// Feature: native-apps-sensor-integration
// Requisiti: 3.4

import SwiftUI
import Charts

/// A compact line + area sparkline for sensor history data.
/// Displays the last 60 data points using catmullRom interpolation.
/// Supports interactive tooltip on touch showing value and time (HH:mm).
/// Y-axis uses fixed scale based on sensor category.
struct SensorSparklineView: View {
    let historyPoints: [SensorHistoryPoint]
    let color: Color
    var category: SensorCategory = .temperature

    @State private var selectedIndex: Int? = nil

    /// Fixed Y scale based on category
    private var yMin: Double { category == .power ? 1 : 10 }
    private var yMax: Double { category == .power ? 100 : 65 }

    /// Data points from the last 60 history entries.
    private var points: [SensorHistoryPoint] {
        Array(historyPoints.suffix(60))
    }

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                LineMark(
                    x: .value("Index", index),
                    y: .value("Valore", point.v)
                )
                .foregroundStyle(color.gradient)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Index", index),
                    y: .value("Valore", point.v)
                )
                .foregroundStyle(color.opacity(0.1).gradient)
                .interpolationMethod(.catmullRom)
            }

            // Selection indicator
            if let idx = selectedIndex, idx >= 0, idx < points.count {
                let point = points[idx]
                RuleMark(x: .value("Index", idx))
                    .foregroundStyle(color.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 4) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f", point.v))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(color)
                            Text(extractTime(from: point.t))
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
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x
                                let plotWidth = geometry.size.width
                                guard plotWidth > 0, !points.isEmpty else { return }
                                let ratio = x / plotWidth
                                let index = Int(ratio * Double(points.count - 1))
                                let clamped = max(0, min(points.count - 1, index))
                                if clamped != selectedIndex {
                                    selectedIndex = clamped
                                    #if os(iOS)
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                    #endif
                                }
                            }
                            .onEnded { _ in
                                selectedIndex = nil
                            }
                    )
            }
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
