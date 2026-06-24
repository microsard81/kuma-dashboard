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
    var unit: String = ""

    @State private var selectedIndex: Int? = nil

    /// Fixed Y scale based on unit
    private var yMin: Double {
        switch unit.lowercased() {
        case "°c": return 15
        case "v": return 0
        case "%": return 0
        case "min": return 1
        case "kw": return 0
        default:
            return category == .power ? 0 : 15
        }
    }

    private var yMax: Double {
        switch unit.lowercased() {
        case "°c": return 60
        case "v": return 250
        case "%": return 100
        case "min": return 280
        case "kw": return 100
        default:
            return category == .power ? 100 : 60
        }
    }

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
                        y: .value("Valore", point.numericValue ?? 0)
                    )
                    .foregroundStyle(color.gradient)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Index", index),
                        y: .value("Valore", point.numericValue ?? 0)
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
                        Text(String(format: "%.1f", point.numericValue ?? 0))
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

            // Touch gesture overlay — UIKit long press that doesn't block scroll
            GeometryReader { geometry in
                SensorScrubGestureOverlay(
                    onActivated: { location in
                        let idx = indexForX(location.x, width: geometry.size.width)
                        if idx != selectedIndex {
                            selectedIndex = idx
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                    },
                    onMoved: { location in
                        let idx = indexForX(location.x, width: geometry.size.width)
                        if idx != selectedIndex {
                            selectedIndex = idx
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                    },
                    onEnded: {
                        selectedIndex = nil
                    }
                )
            }
        }
    }

    private func indexForX(_ x: CGFloat, width: CGFloat) -> Int {
        guard width > 0, !points.isEmpty else { return 0 }
        let ratio = max(0, min(1, x / width))
        return max(0, min(points.count - 1, Int(round(ratio * Double(points.count - 1)))))
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

    /// Extract HH:mm from a raw timestamp string, converting UTC to Europe/Rome
    private func extractTimeFromString(_ str: String) -> String {
        guard !str.isEmpty, str != "null", str != "None", str.count > 4 else { return "" }

        // Try full ISO 8601 parsing and convert to Rome timezone
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFormatter.date(from: str)
        if date == nil {
            isoFormatter.formatOptions = [.withInternetDateTime]
            date = isoFormatter.date(from: str)
        }
        // Try "yyyy-MM-dd HH:mm:ss" format (UTC)
        if date == nil {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            df.timeZone = TimeZone(identifier: "UTC")
            date = df.date(from: str)
        }
        // Try "yyyy-MM-dd'T'HH:mm:ss" without timezone (assume UTC)
        if date == nil {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            df.timeZone = TimeZone(identifier: "UTC")
            date = df.date(from: str)
        }

        if let date = date {
            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = "HH:mm"
            outputFormatter.timeZone = TimeZone(identifier: "Europe/Rome")
            return outputFormatter.string(from: date)
        }

        return ""
    }
}

// MARK: - SensorScrubGestureOverlay (UIKit — doesn't block scroll)

#if os(iOS)
private struct SensorScrubGestureOverlay: UIViewRepresentable {
    let onActivated: (CGPoint) -> Void
    let onMoved: (CGPoint) -> Void
    let onEnded: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.2
        longPress.allowableMovement = .greatestFiniteMagnitude
        longPress.cancelsTouchesInView = false
        longPress.delaysTouchesBegan = false
        view.addGestureRecognizer(longPress)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onActivated = onActivated
        context.coordinator.onMoved = onMoved
        context.coordinator.onEnded = onEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onActivated: onActivated, onMoved: onMoved, onEnded: onEnded)
    }

    final class Coordinator: NSObject {
        var onActivated: (CGPoint) -> Void
        var onMoved: (CGPoint) -> Void
        var onEnded: () -> Void

        init(onActivated: @escaping (CGPoint) -> Void,
             onMoved: @escaping (CGPoint) -> Void,
             onEnded: @escaping () -> Void) {
            self.onActivated = onActivated
            self.onMoved = onMoved
            self.onEnded = onEnded
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)

            switch gesture.state {
            case .began:
                findScrollView(in: view)?.isScrollEnabled = false
                onActivated(location)
            case .changed:
                onMoved(location)
            case .ended, .cancelled, .failed:
                findScrollView(in: view)?.isScrollEnabled = true
                onEnded()
            default:
                break
            }
        }

        private func findScrollView(in view: UIView) -> UIScrollView? {
            var current: UIView? = view.superview
            while let v = current {
                if let scrollView = v as? UIScrollView { return scrollView }
                current = v.superview
            }
            return nil
        }
    }
}
#else
// macOS fallback — simple hover gesture
private struct SensorScrubGestureOverlay: View {
    let onActivated: (CGPoint) -> Void
    let onMoved: (CGPoint) -> Void
    let onEnded: () -> Void

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    onMoved(location)
                case .ended:
                    onEnded()
                }
            }
    }
}
#endif

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
