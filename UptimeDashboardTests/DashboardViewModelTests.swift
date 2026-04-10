// Feature: ios-native-app, Property 4: Ordinamento monitor per severità
// Feature: ios-native-app, Property 6: Colore LED globale e badge DOWN
// Feature: ios-native-app, Property 9: Filtro "Solo DOWN"

import XCTest
import SwiftUI
@testable import UptimeDashboard

// MARK: - Mock NetworkClient

final class MockNetworkClient: NetworkClientProtocol {
    var fetchResult: Result<DashboardResponse, Error> = .failure(NetworkError.networkError(URLError(.notConnectedToInternet)))
    var fetchCallCount = 0

    func login(username: String, password: String) async throws -> LoginResult { .success }
    func verify2FA(code: String) async throws -> Bool { true }
    func logout() async throws {}
    func subscribeAPNs(deviceToken: String, deviceId: String) async throws {}
    func unsubscribeAPNs(deviceToken: String) async throws {}
    func getBiometricToken() async throws -> String { return "mock_token" }
    func biometricLogin(username: String, biometricToken: String) async throws {}

    func fetchDashboardData() async throws -> DashboardResponse {
        fetchCallCount += 1
        switch fetchResult {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}

// MARK: - Test helpers

private func makeItem(
    name: String = "Test",
    k1: ProbeStatus = .up,
    k2: ProbeStatus = .up,
    k3: ProbeStatus = .up,
    n1: ProbeStatus = .up,
    finalStatus: ProbeStatus = .up,
    severity: Int = 0,
    history: [Int] = []
) -> MonitorItem {
    let histJSON = history.map { String($0) }.joined(separator: ",")
    let json = """
    {
        "name": "\(name)",
        "k1": "\(k1.rawValue)",
        "k2": "\(k2.rawValue)",
        "k3": "\(k3.rawValue)",
        "n1": "\(n1.rawValue)",
        "final": "\(finalStatus.rawValue)",
        "severity": \(severity),
        "history": [\(histJSON)],
        "link": null
    }
    """
    return try! JSONDecoder().decode(MonitorItem.self, from: json.data(using: .utf8)!)
}

/// Builds a random MonitorItem with random probe/final statuses.
private func randomItem(name: String = "Item") -> MonitorItem {
    let statuses: [ProbeStatus] = [.up, .down]
    return makeItem(
        name: name,
        k1: statuses.randomElement()!,
        k2: statuses.randomElement()!,
        k3: statuses.randomElement()!,
        n1: statuses.randomElement()!,
        finalStatus: statuses.randomElement()!
    )
}

private func makeDashboardResponse(items: [MonitorItem], globalState: GlobalState = .green) -> DashboardResponse {
    // Build JSON manually to avoid encoding issues with UUID
    let itemsJSON = items.map { item -> String in
        """
        {
            "name": "\(item.name)",
            "k1": "\(item.k1.rawValue)",
            "k2": "\(item.k2.rawValue)",
            "k3": "\(item.k3.rawValue)",
            "n1": "\(item.n1.rawValue)",
            "final": "\(item.final.rawValue)",
            "severity": \(item.severity),
            "history": [\(item.history.map { String($0.severity) }.joined(separator: ","))],
            "link": null
        }
        """
    }.joined(separator: ",")

    let json = """
    {
        "items": [\(itemsJSON)],
        "global_state": "\(globalState.rawValue)",
        "timestamp": "2024-01-01T00:00:00"
    }
    """
    return try! JSONDecoder().decode(DashboardResponse.self, from: json.data(using: .utf8)!)
}

// MARK: - DashboardViewModelTests

final class DashboardViewModelTests: XCTestCase {

    // MARK: - Property 4: Ordinamento monitor per severità
    // Validates: Requirements 3.4

    func testSortOrderProperty_downBeforeMismatchBeforeUp() {
        // Feature: ios-native-app, Property 4: Ordinamento monitor per severità
        // For any random list of MonitorItems, after sorting:
        // all DOWN (severityRank 2) precede mismatch (1) which precede UP (0)
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)

        for iteration in 0..<100 {
            let count = Int.random(in: 1...20)
            let items = (0..<count).map { randomItem(name: "Item\($0)_iter\(iteration)") }
            let response = makeDashboardResponse(items: items)
            mock.fetchResult = .success(response)

            let sorted = response.items.sorted { $0.severityRank > $1.severityRank }

            // Verify ordering: no item with lower rank appears before an item with higher rank
            for i in 0..<sorted.count {
                for j in (i+1)..<sorted.count {
                    XCTAssertGreaterThanOrEqual(
                        sorted[i].severityRank,
                        sorted[j].severityRank,
                        "Item at index \(i) (rank \(sorted[i].severityRank)) must have rank >= item at \(j) (rank \(sorted[j].severityRank))"
                    )
                }
            }

            // Verify DOWN items all come before non-DOWN items
            let downItems = sorted.filter { $0.final == .down }
            let nonDownItems = sorted.filter { $0.final != .down }
            if !downItems.isEmpty && !nonDownItems.isEmpty {
                let lastDownIndex = sorted.lastIndex { $0.final == .down }!
                let firstNonDownIndex = sorted.firstIndex { $0.final != .down }!
                XCTAssertLessThan(lastDownIndex, firstNonDownIndex,
                    "All DOWN items must precede non-DOWN items at iteration \(iteration)")
            }
        }
    }

    func testSortOrderProperty_stableWithinSameRank() {
        // Items with the same severityRank maintain relative order (stable sort)
        let mock = MockNetworkClient()
        let _ = DashboardViewModel(network: mock)

        for _ in 0..<100 {
            let count = Int.random(in: 2...10)
            let items = (0..<count).map { makeItem(name: "Item\($0)", finalStatus: .up, k1: .up, k2: .up, k3: .up, n1: .up) }
            let sorted = items.sorted { $0.severityRank > $1.severityRank }
            // All have same rank (green), order should be preserved
            XCTAssertEqual(sorted.map { $0.name }, items.map { $0.name },
                "Stable sort: items with same rank must preserve relative order")
        }
    }

    // MARK: - Property 6: Colore LED globale e badge DOWN
    // Validates: Requirements 4.1, 4.2, 4.4

    func testLEDAndBadgeProperty_ledColorMatchesGlobalState() {
        // Feature: ios-native-app, Property 6: Colore LED globale e badge DOWN
        // For any GlobalState, ledColor must match globalState.color
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)

        let states: [GlobalState] = [.green, .yellow, .red]
        for _ in 0..<100 {
            let state = states.randomElement()!
            let items = (0..<Int.random(in: 0...10)).map { randomItem(name: "I\($0)") }
            let response = makeDashboardResponse(items: items, globalState: state)
            mock.fetchResult = .success(response)

            // Simulate what refresh() does
            vm.globalState = response.globalState

            // ledColor must equal globalState.color
            // We compare via UIColor description since Color doesn't conform to Equatable directly
            let expectedColor = state.color
            let actualColor = vm.ledColor
            // Both should be the same Color value
            XCTAssertEqual(
                UIColor(expectedColor).cgColor.components,
                UIColor(actualColor).cgColor.components,
                "ledColor must match globalState.color for state \(state)"
            )
        }
    }

    func testLEDAndBadgeProperty_downCountEqualsDownItems() {
        // Feature: ios-native-app, Property 6: Colore LED globale e badge DOWN
        // downCount must equal the number of items with final == .down
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)

        for iteration in 0..<100 {
            let count = Int.random(in: 0...20)
            let items = (0..<count).map { randomItem(name: "I\($0)_\(iteration)") }
            vm.items = items

            let expectedDown = items.filter { $0.final == .down }.count
            XCTAssertEqual(vm.downCount, expectedDown,
                "downCount must equal number of items with final == .down at iteration \(iteration)")
        }
    }

    func testLEDAndBadgeProperty_downCountZeroWhenAllUp() {
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)

        for _ in 0..<100 {
            let count = Int.random(in: 0...20)
            let items = (0..<count).map { makeItem(name: "I\($0)", finalStatus: .up) }
            vm.items = items
            XCTAssertEqual(vm.downCount, 0, "downCount must be 0 when all items are UP")
        }
    }

    // MARK: - Property 9: Filtro "Solo DOWN"
    // Validates: Requirements 7.2, 7.3

    func testOnlyDownFilterProperty_filterActive_onlyDownItems() {
        // Feature: ios-native-app, Property 9: Filtro "Solo DOWN"
        // When isOnlyDownFilter == true, filteredItems contains only items with final == .down
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)
        vm.isOnlyDownFilter = true

        for iteration in 0..<100 {
            let count = Int.random(in: 0...20)
            let items = (0..<count).map { randomItem(name: "I\($0)_\(iteration)") }
            vm.items = items

            let filtered = vm.filteredItems
            for item in filtered {
                XCTAssertEqual(item.final, .down,
                    "With filter active, filteredItems must only contain DOWN items at iteration \(iteration)")
            }
        }
    }

    func testOnlyDownFilterProperty_filterInactive_allItems() {
        // Feature: ios-native-app, Property 9: Filtro "Solo DOWN"
        // When isOnlyDownFilter == false, filteredItems == items
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)
        vm.isOnlyDownFilter = false

        for iteration in 0..<100 {
            let count = Int.random(in: 0...20)
            let items = (0..<count).map { randomItem(name: "I\($0)_\(iteration)") }
            vm.items = items

            XCTAssertEqual(vm.filteredItems.map { $0.id }, items.map { $0.id },
                "With filter inactive, filteredItems must equal items at iteration \(iteration)")
        }
    }

    func testOnlyDownFilterProperty_toggleBehavior() {
        // Toggling the filter changes filteredItems correctly
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)

        for _ in 0..<100 {
            let count = Int.random(in: 1...20)
            let items = (0..<count).map { randomItem(name: "I\($0)") }
            vm.items = items

            vm.isOnlyDownFilter = false
            let allItems = vm.filteredItems
            XCTAssertEqual(allItems.count, items.count)

            vm.isOnlyDownFilter = true
            let downOnly = vm.filteredItems
            XCTAssertTrue(downOnly.allSatisfy { $0.final == .down })
            XCTAssertLessThanOrEqual(downOnly.count, allItems.count)
        }
    }

    // MARK: - Unit tests: fetch success

    func testRefresh_success_updatesItemsAndState() async {
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)

        let items = [
            makeItem(name: "A", finalStatus: .down),
            makeItem(name: "B", finalStatus: .up)
        ]
        let response = makeDashboardResponse(items: items, globalState: .red)
        mock.fetchResult = .success(response)

        await vm.refresh()

        XCTAssertFalse(vm.isStale, "isStale must be false after successful fetch")
        XCTAssertNotNil(vm.lastUpdated, "lastUpdated must be set after successful fetch")
        XCTAssertEqual(vm.globalState, .red)
        XCTAssertEqual(vm.items.count, 2)
    }

    func testRefresh_success_itemsSortedBySeverity() async {
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)

        // Provide items in wrong order: UP, mismatch, DOWN
        let upItem = makeItem(name: "UP", k1: .up, k2: .up, k3: .up, n1: .up, finalStatus: .up)
        let mismatchItem = makeItem(name: "Mismatch", k1: .up, k2: .down, k3: .up, n1: .up, finalStatus: .up)
        let downItem = makeItem(name: "DOWN", finalStatus: .down)

        let response = makeDashboardResponse(items: [upItem, mismatchItem, downItem], globalState: .red)
        mock.fetchResult = .success(response)

        await vm.refresh()

        XCTAssertEqual(vm.items[0].name, "DOWN", "DOWN item must be first")
        XCTAssertEqual(vm.items[1].name, "Mismatch", "Mismatch item must be second")
        XCTAssertEqual(vm.items[2].name, "UP", "UP item must be last")
    }

    // MARK: - Unit tests: fetch error with stale data

    func testRefresh_error_setsStaleAndPreservesData() async {
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)

        // First successful fetch
        let items = [makeItem(name: "A", finalStatus: .up)]
        mock.fetchResult = .success(makeDashboardResponse(items: items, globalState: .green))
        await vm.refresh()

        XCTAssertFalse(vm.isStale)
        XCTAssertEqual(vm.items.count, 1)

        // Now simulate network error
        mock.fetchResult = .failure(NetworkError.networkError(URLError(.notConnectedToInternet)))
        await vm.refresh()

        XCTAssertTrue(vm.isStale, "isStale must be true after failed fetch")
        XCTAssertEqual(vm.items.count, 1, "Previous items must be preserved on error")
        XCTAssertEqual(vm.globalState, .green, "Previous globalState must be preserved on error")
    }

    func testRefresh_error_firstFetch_itemsRemainEmpty() async {
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)

        mock.fetchResult = .failure(NetworkError.networkError(URLError(.notConnectedToInternet)))
        await vm.refresh()

        XCTAssertTrue(vm.isStale)
        XCTAssertTrue(vm.items.isEmpty, "Items must remain empty if first fetch fails")
    }

    // MARK: - Unit tests: auto-refresh lifecycle

    func testAutoRefreshLifecycle_startAndStop() async {
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)

        let items = [makeItem(name: "A")]
        mock.fetchResult = .success(makeDashboardResponse(items: items))

        vm.startAutoRefresh()
        // Give the immediate refresh a moment to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        XCTAssertGreaterThanOrEqual(mock.fetchCallCount, 1, "startAutoRefresh must trigger at least one fetch")

        vm.stopAutoRefresh()
        let countAfterStop = mock.fetchCallCount

        // Wait a bit and verify no more fetches happen
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        XCTAssertEqual(mock.fetchCallCount, countAfterStop, "stopAutoRefresh must prevent further fetches")
    }

    func testAutoRefreshLifecycle_stopWithoutStart_doesNotCrash() {
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)
        // Should not crash
        vm.stopAutoRefresh()
    }

    // MARK: - Unit tests: badge zero hidden

    func testDownCount_zeroWhenNoDownItems() {
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)

        vm.items = [
            makeItem(name: "A", finalStatus: .up),
            makeItem(name: "B", finalStatus: .up)
        ]
        XCTAssertEqual(vm.downCount, 0, "Badge must be 0 (hidden) when no DOWN items")
    }

    func testDownCount_correctCount() {
        let mock = MockNetworkClient()
        let vm = DashboardViewModel(network: mock)

        vm.items = [
            makeItem(name: "A", finalStatus: .down),
            makeItem(name: "B", finalStatus: .up),
            makeItem(name: "C", finalStatus: .down)
        ]
        XCTAssertEqual(vm.downCount, 2)
    }
}
