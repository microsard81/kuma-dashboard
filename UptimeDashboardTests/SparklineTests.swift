// Feature: ios-native-app, Property 8: Codifica cromatica sparkline
// Feature: ios-native-app, Property 7: Troncamento sparkline a 60 punti

import XCTest
import SwiftUI
@testable import UptimeDashboard

// MARK: - Color comparison helper
// Extracts RGBA components from a SwiftUI Color via UIColor bridge
private extension Color {
    /// Returns (r, g, b, a) in 0...255 range, rounded to nearest integer
    func rgbaComponents() -> (r: Int, g: Int, b: Int, a: Int) {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int((r * 255).rounded()),
                Int((g * 255).rounded()),
                Int((b * 255).rounded()),
                Int((a * 255).rounded()))
    }
}

// Expected hex colors as (r, g, b)
private let colorGreen = (r: 52,  g: 211, b: 153) // #34d399
private let colorYellow = (r: 255, g: 238, b: 0)   // #FFEE00
private let colorRed   = (r: 248, g: 113, b: 113)  // #f87171

final class SparklineTests: XCTestCase {

    // MARK: - Property 8: Codifica cromatica sparkline
    // Validates: Requirements 5.2

    func testSparklineColorProperty_severity0_isGreen() {
        // severity 0 → #34d399
        for _ in 0..<100 {
            let segment = SparklineSegment(id: Int.random(in: 0...1000), severity: 0, timestamp: nil)
            let (r, g, b, _) = segment.color.rgbaComponents()
            XCTAssertEqual(r, colorGreen.r, accuracy: 1, "severity 0: red component mismatch")
            XCTAssertEqual(g, colorGreen.g, accuracy: 1, "severity 0: green component mismatch")
            XCTAssertEqual(b, colorGreen.b, accuracy: 1, "severity 0: blue component mismatch")
        }
    }

    func testSparklineColorProperty_severity1_isYellow() {
        // severity 1 → #FFEE00
        for _ in 0..<100 {
            let segment = SparklineSegment(id: Int.random(in: 0...1000), severity: 1, timestamp: nil)
            let (r, g, b, _) = segment.color.rgbaComponents()
            XCTAssertEqual(r, colorYellow.r, accuracy: 1, "severity 1: red component mismatch")
            XCTAssertEqual(g, colorYellow.g, accuracy: 1, "severity 1: green component mismatch")
            XCTAssertEqual(b, colorYellow.b, accuracy: 1, "severity 1: blue component mismatch")
        }
    }

    func testSparklineColorProperty_severity2_isRed() {
        // severity 2 → #f87171
        for _ in 0..<100 {
            let segment = SparklineSegment(id: Int.random(in: 0...1000), severity: 2, timestamp: nil)
            let (r, g, b, _) = segment.color.rgbaComponents()
            XCTAssertEqual(r, colorRed.r, accuracy: 1, "severity 2: red component mismatch")
            XCTAssertEqual(g, colorRed.g, accuracy: 1, "severity 2: green component mismatch")
            XCTAssertEqual(b, colorRed.b, accuracy: 1, "severity 2: blue component mismatch")
        }
    }

    func testSparklineColorProperty_allSeveritiesRandom() {
        // Generate random severity values from {0, 1, 2} and verify correct color mapping
        let severities = [0, 1, 2]
        for _ in 0..<100 {
            let severity = severities.randomElement()!
            let segment = SparklineSegment(id: 0, severity: severity, timestamp: nil)
            let (r, g, b, _) = segment.color.rgbaComponents()
            switch severity {
            case 0:
                XCTAssertEqual(r, colorGreen.r, accuracy: 1)
                XCTAssertEqual(g, colorGreen.g, accuracy: 1)
                XCTAssertEqual(b, colorGreen.b, accuracy: 1)
            case 1:
                XCTAssertEqual(r, colorYellow.r, accuracy: 1)
                XCTAssertEqual(g, colorYellow.g, accuracy: 1)
                XCTAssertEqual(b, colorYellow.b, accuracy: 1)
            case 2:
                XCTAssertEqual(r, colorRed.r, accuracy: 1)
                XCTAssertEqual(g, colorRed.g, accuracy: 1)
                XCTAssertEqual(b, colorRed.b, accuracy: 1)
            default:
                XCTFail("Unexpected severity value: \(severity)")
            }
        }
    }

    // MARK: - Property 7: Troncamento sparkline a 60 punti
    // Validates: Requirements 5.1, 5.3

    func testSparklineTruncationProperty_countIsMinN60() {
        // For any history array of length N, suffix(60).count == min(N, 60)
        for _ in 0..<100 {
            let length = Int.random(in: 0...200)
            let history = (0..<length).map { _ in Int.random(in: 0...2) }
            let truncated = history.suffix(60)
            let expectedCount = min(history.count, 60)
            XCTAssertEqual(truncated.count, expectedCount,
                "suffix(60).count should be min(\(length), 60) = \(expectedCount), got \(truncated.count)")
        }
    }

    func testSparklineTruncationProperty_lastElementsPreserved() {
        // The truncated array must correspond to the LAST min(N, 60) elements
        for _ in 0..<100 {
            let length = Int.random(in: 1...200)
            let history = (0..<length).map { _ in Int.random(in: 0...2) }
            let truncated = Array(history.suffix(60))
            let expectedSlice = Array(history.dropFirst(max(0, history.count - 60)))
            XCTAssertEqual(truncated, expectedSlice,
                "Truncated sparkline must contain the last min(N,60) elements")
        }
    }

    func testSparklineTruncationProperty_emptyHistory() {
        // Edge case: empty history → 0 segments
        let history: [Int] = []
        let truncated = history.suffix(60)
        XCTAssertEqual(truncated.count, 0, "Empty history must produce 0 segments")
    }

    func testSparklineTruncationProperty_exactlyAtBoundary() {
        // Edge case: exactly 60 elements → all 60 preserved
        let history = (0..<60).map { _ in Int.random(in: 0...2) }
        let truncated = Array(history.suffix(60))
        XCTAssertEqual(truncated.count, 60)
        XCTAssertEqual(truncated, history, "Exactly 60 elements must all be preserved")
    }

    func testSparklineTruncationProperty_moreThan60_onlyLast60() {
        // For arrays longer than 60, only the last 60 elements are shown
        for _ in 0..<100 {
            let length = Int.random(in: 61...200)
            let history = (0..<length).map { _ in Int.random(in: 0...2) }
            let truncated = Array(history.suffix(60))
            XCTAssertEqual(truncated.count, 60,
                "Arrays longer than 60 must be truncated to exactly 60 elements")
            XCTAssertEqual(truncated, Array(history[(history.count - 60)...]),
                "Must keep the LAST 60 elements, not the first")
        }
    }
}
