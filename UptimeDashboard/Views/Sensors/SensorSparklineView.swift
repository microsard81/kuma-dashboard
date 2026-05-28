// Feature: native-apps-sensor-integration
// Requisiti: 3.4

import SwiftUI
import Charts

/// A compact line + area sparkline for sensor history data.
/// Displays the last 60 data points using catmullRom interpolation
/// with hidden axes and legend for minimal footprint.
struct SensorSparklineView: View {
    let points: [Double]
    let color: Color

    var body: some View {
        Chart {
            ForEach(Array(points.suffix(60).enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Index", index),
                    y: .value("Value", value)
                )
                .foregroundStyle(color.gradient)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Index", index),
                    y: .value("Value", value)
                )
                .foregroundStyle(color.opacity(0.1).gradient)
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - Preview

#if DEBUG
struct SensorSparklineView_Previews: PreviewProvider {
    static var previews: some View {
        SensorSparklineView(
            points: [23.1, 23.3, 23.5, 24.0, 23.8, 23.6, 23.9, 24.2, 24.1, 23.7],
            color: .green
        )
        .frame(height: 40)
        .padding()
    }
}
#endif
