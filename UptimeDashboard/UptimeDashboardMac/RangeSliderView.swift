import SwiftUI

/// A custom range slider with two draggable thumbs for selecting a min/max range.
struct RangeSliderView: View {
    @Binding var lowerValue: Double
    @Binding var upperValue: Double
    let bounds: ClosedRange<Double>
    var step: Double = 1
    var accentColor: Color = .accentColor

    private let thumbSize: CGFloat = 18
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - thumbSize
            let range = bounds.upperBound - bounds.lowerBound

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(Color.gray.opacity(0.25))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbSize / 2)

                // Active range track
                let lowerX = width * (lowerValue - bounds.lowerBound) / range
                let upperX = width * (upperValue - bounds.lowerBound) / range
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(accentColor)
                    .frame(width: max(0, upperX - lowerX), height: trackHeight)
                    .offset(x: lowerX + thumbSize / 2)

                // Lower thumb
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: lowerX)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let raw = bounds.lowerBound + (value.location.x / width) * range
                                let stepped = round(raw / step) * step
                                let clamped = min(max(stepped, bounds.lowerBound), upperValue - step)
                                lowerValue = clamped
                            }
                    )

                // Upper thumb
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: upperX)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let raw = bounds.lowerBound + (value.location.x / width) * range
                                let stepped = round(raw / step) * step
                                let clamped = max(min(stepped, bounds.upperBound), lowerValue + step)
                                upperValue = clamped
                            }
                    )
            }
            .frame(height: thumbSize)
        }
        .frame(height: thumbSize)
    }
}
