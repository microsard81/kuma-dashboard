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
        ZStack(alignment: .topLeading) {
            // Chart
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
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: yMin...yMax)
            .chartLegend(.hidden)

            // Tooltip overlay
            if let idx = selectedIndex, idx >= 0, idx < points.count {
                let point = points[idx]
                let timeLabel = getTimeLabel(for: idx, point: point)
                GeometryReader { geo in
                    let xPos = geo.size.width * CGFloat(idx) / CGFloat(max(points.count - 1, 1))
                    VStack(spacing: 1) {
                        Text(String(format: "%.1f", point.v))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(color)
                        Text(timeLabel)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .position(x: min(max(xPos, 30), geo.size.width - 30), y: 12)
                }
            }

            // Touch gesture overlay (200ms delay before showing tooltip)
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        LongPressGesture(minimumDuration: 0.2)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { value in
                                switch value {
                                case .second(true, let drag):
                                    guard let drag = drag else { return }
                                    let x = drag.location.x
                                    let plotWidth = geometry.size.width
                                    guard plotWidth > 0, !points.isEmpty else { return }
                                    let ratio = max(0, min(1, x / plotWidth))
                                    let index = Int(round(ratio * Double(points.count - 1)))
                                    let clamped = max(0, min(points.count - 1, index))
                                    if clamped != selectedIndex {
                                        selectedIndex = clamped
                                        #if os(iOS)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                    }
                                default:
                                    break
                                }
                            }
                            .onEnded { _ in
                                selectedIndex = nil
                            }
                    )
                            }
                    )
            }
        }
    }

    /// Get time label for a point. Tries to extract from the t field first,
    /// falls back to calculating from position (1 point = 1 minute, last = now).
    private func getTimeLabel(for index: Int, point: SensorHistoryPoint) -> String {
        // Try to extract time from the t field
        let extracted = extractTimeFromString(point.t)
        if !extracted.isEmpty {
            return extracted
        }
        // Fallback: calculate time assuming 1-minute intervals, last point = now
        let minutesAgo = points.count - 1 - index
        let date = Date().addingTimeInterval(-Double(minutesAgo) * 60)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Extract HH:mm from a raw timestamp string
    private func extractTimeFromString(_ str: String) -> String {
        guard !str.isEmpty, str != "null", str != "None", str.count > 4 else { return "" }
        // Look for T followed by HH:mm (e.g. "2026-05-29T08:37:00+00:00")
        if let tIndex = str.firstIndex(of: "T"),
           str.distance(from: str.startIndex, to: tIndex) >= 8 {
            let timeStart = str.index(after: tIndex)
            if str.distance(from: timeStart, to: str.endIndex) >= 5 {
                return String(str[timeStart...].prefix(5))
            }
        }
        // Look for space followed by HH:mm (e.g. "2026-05-29 08:37:00")
        if let spaceIndex = str.lastIndex(of: " ") {
            let timeStart = str.index(after: spaceIndex)
            if str.distance(from: timeStart, to: str.endIndex) >= 5 {
                return String(str[timeStart...].prefix(5))
            }
        }
        return ""
    }
}

// MARK: - Legacy convenience init (backward compatibility)
extension SensorSparklineView {
    init(points: [Double], color: Color) {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let syntheticPoints = points.suffix(60).enumerated().map { index, value in
            let date = now.addingTimeInterval(Double(index - points.suffix(60).count) * 60)
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
