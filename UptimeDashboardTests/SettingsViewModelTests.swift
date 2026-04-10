// Feature: ios-native-app, Property 11: Round-trip persistenza tema

import XCTest
@testable import UptimeDashboard

final class SettingsViewModelTests: XCTestCase {

    // MARK: - Property 11: Round-trip persistenza tema
    // Validates: Requirements 8.3

    func testThemePersistenceProperty_savedValueReloadsIdentically() {
        // For any ThemeMode, saving via cycleTheme() and reloading via a new
        // SettingsViewModel instance must return the identical value.
        // Uses isolated UserDefaults to avoid cross-test contamination.
        for _ in 0..<100 {
            let target = ThemeMode.allCases.randomElement()!
            let suite = UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!

            // Cycle from .auto until we reach the target value
            let vm = SettingsViewModel(defaults: defaults)
            // SettingsViewModel starts at .auto (or whatever was persisted — fresh suite starts at .auto)
            var steps = 0
            while vm.themeMode != target && steps < 3 {
                vm.cycleTheme()
                steps += 1
            }
            XCTAssertEqual(vm.themeMode, target,
                "Could not reach target .\(target) via cycleTheme()")

            // Create a new instance with the same UserDefaults suite
            let reloaded = SettingsViewModel(defaults: defaults)
            XCTAssertEqual(reloaded.themeMode, target,
                "Reloaded SettingsViewModel must have themeMode == .\(target), got .\(reloaded.themeMode)")

            // Clean up
            defaults.removePersistentDomain(forName: suite)
        }
    }

    func testThemePersistenceProperty_allModesRoundTrip() {
        // Exhaustive: every ThemeMode persists and reloads correctly
        for mode in ThemeMode.allCases {
            let suite = UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!

            // Write the raw value directly to simulate any possible saved state
            defaults.set(mode.rawValue, forKey: "themeMode")

            let vm = SettingsViewModel(defaults: defaults)
            XCTAssertEqual(vm.themeMode, mode,
                "SettingsViewModel must load .\(mode) from UserDefaults")

            defaults.removePersistentDomain(forName: suite)
        }
    }

    func testThemePersistenceProperty_defaultsToAutoWhenNoValueSaved() {
        // When no value is persisted, themeMode must default to .auto
        for _ in 0..<100 {
            let suite = UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!
            // Do NOT write anything

            let vm = SettingsViewModel(defaults: defaults)
            XCTAssertEqual(vm.themeMode, .auto,
                "SettingsViewModel must default to .auto when no value is saved")

            defaults.removePersistentDomain(forName: suite)
        }
    }

    func testCycleTheme_persistsAfterEachCycle() {
        // Each call to cycleTheme() must persist the new value immediately
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let vm = SettingsViewModel(defaults: defaults)

        var expected = ThemeMode.auto
        for _ in 0..<100 {
            vm.cycleTheme()
            expected = expected.next

            XCTAssertEqual(vm.themeMode, expected)

            // Verify persistence by reading raw value directly
            let raw = defaults.string(forKey: "themeMode")
            XCTAssertEqual(raw, expected.rawValue,
                "UserDefaults must contain '\(expected.rawValue)' after cycleTheme()")
        }

        defaults.removePersistentDomain(forName: suite)
    }
}
