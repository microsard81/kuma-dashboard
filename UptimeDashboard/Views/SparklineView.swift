// Feature: ios-native-app
// Requisiti: 5.1, 5.2, 5.3, 5.4

import SwiftUI
import UIKit

// MARK: - SparklineView

struct SparklineView: View {
    /// Raw history array of HistoryPoint.
    let history: [HistoryPoint]

    /// Binding to communicate the selected segment to the parent view.
    @Binding var selectedSegment: SparklineSegment?

    /// Whether haptic feedback is enabled during scrubbing.
    var hapticEnabled: Bool = true

    /// History sampling interval in seconds (matches backend worker cycle).
    private let samplingInterval: TimeInterval = 60

    // MARK: - Fisheye configuration
    private let maxScale: CGFloat = 1.5
    private let spread: CGFloat = 3.0

    // MARK: - State
    @State private var dragX: CGFloat? = nil
    @State private var isScrubbing: Bool = false

    /// Computed segments — at most the last 60 points, with estimated timestamps.
    private var segments: [SparklineSegment] {
        let slice = Array(history.suffix(60))
        let now = Date()
        return slice.enumerated().map { offset, point in
            let secsAgo = TimeInterval(slice.count - 1 - offset) * samplingInterval
            let timestamp = now.addingTimeInterval(-secsAgo)
            return SparklineSegment(
                id: offset,
                severity: point.severity,
                timestamp: timestamp,
                k1: point.k1,
                k2: point.k2,
                k3: point.k3,
                n1: point.n1
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            let count = segments.count
            let baseBarWidth = barWidth(totalWidth: geo.size.width, count: count)
            let cellWidth = baseBarWidth + 1.0

            ZStack {
                // Bars
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(segments) { segment in
                        let scale = scaleFor(index: segment.id, cellWidth: cellWidth)
                        Rectangle()
                            .fill(segment.color)
                            .frame(
                                width: baseBarWidth,
                                height: geo.size.height * scale
                            )
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                // Gesture overlay — UIKit long press that doesn't block scroll
                ScrubGestureOverlay(
                    onActivated: { location in
                        if hapticEnabled {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                        }
                        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.7)) {
                            isScrubbing = true
                            dragX = location.x
                        }
                        updateSelection(x: location.x, cellWidth: cellWidth, count: count)
                    },
                    onMoved: { location in
                        guard isScrubbing else { return }
                        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.7)) {
                            dragX = location.x
                        }
                        updateSelection(x: location.x, cellWidth: cellWidth, count: count)
                    },
                    onEnded: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            dragX = nil
                            isScrubbing = false
                        }
                        selectedSegment = nil
                    }
                )
            }
        }
    }

    // MARK: - Helpers

    private func updateSelection(x: CGFloat, cellWidth: CGFloat, count: Int) {
        let idx = indexForLocation(x, cellWidth: cellWidth)
        if idx >= 0, idx < count {
            let newSegment = segments[idx]
            if hapticEnabled, newSegment.id != selectedSegment?.id {
                let generator = UISelectionFeedbackGenerator()
                generator.selectionChanged()
            }
            selectedSegment = newSegment
        }
    }

    private func scaleFor(index: Int, cellWidth: CGFloat) -> CGFloat {
        guard let x = dragX, isScrubbing else { return 1.0 }
        let barCenter = CGFloat(index) * cellWidth + cellWidth / 2.0
        let distance = abs(x - barCenter) / cellWidth
        let gaussian = exp(-(distance * distance) / (2.0 * spread * spread))
        return 1.0 + (maxScale - 1.0) * gaussian
    }

    private func barWidth(totalWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let spacing = CGFloat(count - 1) * 1.0
        return max(1, (totalWidth - spacing) / CGFloat(count))
    }

    private func indexForLocation(_ x: CGFloat, cellWidth: CGFloat) -> Int {
        guard cellWidth > 0 else { return -1 }
        return Int(x / cellWidth)
    }
}


// MARK: - ScrubGestureOverlay (UIKit)

/// A UIViewRepresentable that uses UILongPressGestureRecognizer to detect a long press
/// before activating scrubbing. This does NOT block the parent UIScrollView (List scroll)
/// for quick swipes — only activates after the finger stays still for 100ms.
private struct ScrubGestureOverlay: UIViewRepresentable {
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
        longPress.minimumPressDuration = 0.1
        longPress.allowableMovement = .greatestFiniteMagnitude // Don't cancel on movement after activation
        longPress.cancelsTouchesInView = false // Let scroll view receive touches initially
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
                // Long press recognized — activate scrubbing
                // Disable scroll on the parent UIScrollView so we own the touch
                findScrollView(in: view)?.isScrollEnabled = false
                onActivated(location)
            case .changed:
                onMoved(location)
            case .ended, .cancelled, .failed:
                // Re-enable scroll
                findScrollView(in: view)?.isScrollEnabled = true
                onEnded()
            default:
                break
            }
        }

        /// Walk up the view hierarchy to find the enclosing UIScrollView (the List).
        private func findScrollView(in view: UIView) -> UIScrollView? {
            var current: UIView? = view.superview
            while let v = current {
                if let scrollView = v as? UIScrollView {
                    return scrollView
                }
                current = v.superview
            }
            return nil
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SparklineView_Previews: PreviewProvider {
    static var previews: some View {
        SparklineView(
            history: [
                HistoryPoint(severity: 0), HistoryPoint(severity: 0),
                HistoryPoint(severity: 1, k1: 0, k2: 1, k3: 0, n1: 0),
                HistoryPoint(severity: 2), HistoryPoint(severity: 0),
            ],
            selectedSegment: .constant(nil),
            hapticEnabled: true
        )
        .frame(height: 28)
        .padding()
    }
}
#endif
