// Feature: native-apps-sensor-integration
// Requisiti: 3.4

import SwiftUI
import Charts

/// A compact line + area sparkline for sensor history data.
/// Displays the last 60 data points using catmullRom interpolation.
/// Supports interactive tooltip on touch/hover showing value and time (HH:mm).
struct SensorSparklineView: View {
    let historyPoints: [SensorHistoryPoint]
    let color: Color

    @State private var selectedIndex: Int? = nil

    /// Parsed data points with Date for tooltip display.
    private var dataPoints: [(date: Date, value: Double, index: Int)] {
        historyPoints.suffix(60).enumerated().compactMap { index, point in
            guard let date = parseISO(point.t) else { return nil }
            return (date: date, value: point.v, index: index)
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
                            Text(formatTime(point.date))
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
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedIndex)
        .onChange(of: selectedIndex) { _ in
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Parses an ISO 8601 timestamp string into a Date.
    private func parseISO(_ str: String?) -> Date? {
        guard let str = str else { return nil }
        // Try ISO8601 with fractional seconds
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: str) { return date }
        // Try ISO8601 without fractional seconds
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: str) { return date }
        // Fallback: no timezone (local time assumed)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.date(from: str)
    }
}

// MARK: - Legacy convenience init (backward compatibility)
extension SensorSparklineView {
    /// Legacy initializer accepting raw [Double] points (no timestamps, index-based).
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
            color: .green
        )
        .frame(height: 50)
        .padding()
    }
}
#endif
