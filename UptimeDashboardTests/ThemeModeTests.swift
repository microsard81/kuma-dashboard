// Feature: ios-native-app, Property 10: Ciclo tema deterministico

import XCTest
@testable import UptimeDashboard

final class ThemeModeTests: XCTestCase {

    // MARK: - Property 10: Ciclo tema deterministico
    // Validates: Requirements 8.2

    func testThemeCycleProperty_threeNextCallsReturnOriginal() {
        // For any ThemeMode, applying .next three times must return the original value
        // (full cycle: auto → light → dark → auto)
        for _ in 0..<100 {
            let original = ThemeMode.allCases.randomElement()!
            let cycled = original.next.next.next
            XCTAssertEqual(cycled, original,
                "Applying .next three times to .\(original) must return the original value, got .\(cycled)")
        }
    }

    func testThemeCycleProperty_exhaustiveAllCases() {
        // Verify the cycle holds for every possible starting value
        for mode in ThemeMode.allCases {
            XCTAssertEqual(mode.next.next.next, mode,
                "Cycle must complete in exactly 3 steps for .\(mode)")
        }
    }

    func testThemeCycleProperty_orderIsAutoLightDark() {
        // Verify the specific cycle order: auto → light → dark → auto
        XCTAssertEqual(ThemeMode.auto.next, .light)
        XCTAssertEqual(ThemeMode.light.next, .dark)
        XCTAssertEqual(ThemeMode.dark.next, .auto)
    }

    func testThemeCycleProperty_noDuplicatesInCycle() {
        // A full cycle from any starting point visits all 3 values exactly once
        for start in ThemeMode.allCases {
            let visited = [start, start.next, start.next.next]
            let unique = Set(visited.map { $0.rawValue })
            XCTAssertEqual(unique.count, 3,
                "A full cycle from .\(start) must visit all 3 distinct ThemeMode values")
        }
    }
}
