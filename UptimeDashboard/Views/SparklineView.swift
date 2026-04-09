// Feature: ios-native-app
// Requisiti: 5.1, 5.2, 5.3, 5.4

import SwiftUI

// MARK: - SparklineView

struct SparklineView: View {
    /// Raw history array of severity integers (0 = up, 1 = mismatch, 2 = down).
    let history: [Int]

    /// Binding to communicate the selected segment to the parent view.
    @Binding var selectedSegment: SparklineSegment?

    /// History sampling interval in seconds (matches backend worker cycle).
    private let samplingInterval: TimeInterval = 60

    /// Computed segments — at most the last 60 points, with estimated timestamps.
    private var segments: [SparklineSegment] {
        let slice = Array(history.suffix(60))
        let now = Date()
        return slice.enumerated().map { offset, severity in
            let secsAgo = TimeInterval(slice.count - 1 - offset) * samplingInterval
            let timestamp = now.addingTimeInterval(-secsAgo)
            return SparklineSegment(id: offset, severity: severity, timestamp: timestamp)
        }
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: barWidth(totalWidth: geo.size.width, count: segments.count))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let index = indexForLocation(value.location.x, totalWidth: geo.size.width)
                        if index >= 0, index < segments.count {
                            selectedSegment = segments[index]
                        }
                    }
                    .onEnded { _ in
                        selectedSegment = nil
                    }
            )
        }
    }

    private func barWidth(totalWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let spacing = CGFloat(count - 1) * 1.0
        return max(1, (totalWidth - spacing) / CGFloat(count))
    }

    private func indexForLocation(_ x: CGFloat, totalWidth: CGFloat) -> Int {
        guard !segments.isEmpty else { return -1 }
        let count = segments.count
        let spacing = CGFloat(count - 1) * 1.0
        let bw = max(1, (totalWidth - spacing) / CGFloat(count))
        let cellWidth = bw + 1.0 // bar + spacing
        return Int(x / cellWidth)
    }
}

// MARK: - Preview

#if DEBUG
struct SparklineView_Previews: PreviewProvider {
    static var previews: some View {
        SparklineView(history: [0, 0, 1, 2, 2, 0, 0, 1, 0, 2], selectedSegment: .constant(nil))
            .frame(height: 28)
            .padding()
    }
}
#endif
