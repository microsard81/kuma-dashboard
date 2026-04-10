// Feature: ios-native-app, Property 3: Codifica cromatica delle righe monitor
// Feature: ios-native-app, Property 5: Mapping completo dei campi monitor

import XCTest
@testable import UptimeDashboard

// MARK: - Test helper: build MonitorItem via JSONDecoder
extension MonitorItem {
    static func makeForTest(
        name: String = "Test",
        k1: ProbeStatus = .up,
        k2: ProbeStatus = .up,
        k3: ProbeStatus = .up,
        n1: ProbeStatus = .up,
        final finalStatus: ProbeStatus = .up,
        severity: Int = 0,
        history: [Int] = [],
        link: String? = nil
    ) -> MonitorItem {
        let historyJSON = history.map { String($0) }.joined(separator: ",")
        let linkJSON = link.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
            "name": "\(name)",
            "k1": "\(k1.rawValue)",
            "k2": "\(k2.rawValue)",
            "k3": "\(k3.rawValue)",
            "n1": "\(n1.rawValue)",
            "final": "\(finalStatus.rawValue)",
            "severity": \(severity),
            "history": [\(historyJSON)],
            "link": \(linkJSON)
        }
        """
        let data = json.data(using: .utf8)!
        return try! JSONDecoder().decode(MonitorItem.self, from: data)
    }
}

// MARK: - Random helpers
private func randomProbeStatus() -> ProbeStatus {
    Bool.random() ? .up : .down
}

private func randomProbeStatuses() -> (k1: ProbeStatus, k2: ProbeStatus, k3: ProbeStatus, n1: ProbeStatus) {
    return (randomProbeStatus(), randomProbeStatus(), randomProbeStatus(), randomProbeStatus())
}

final class MonitorItemTests: XCTestCase {

    // MARK: - Property 3: Codifica cromatica delle righe monitor
    // Validates: Requirements 3.3

    func testRowColorProperty_finalDown_alwaysRed() {
        // For any combination of probe statuses, if final == .down → rowColor == .red
        for _ in 0..<100 {
            let (k1, k2, k3, n1) = randomProbeStatuses()
            let item = MonitorItem.makeForTest(k1: k1, k2: k2, k3: k3, n1: n1, final: .down)
            XCTAssertEqual(item.rowColor, .red,
                "Expected .red when final == .down (k1:\(k1), k2:\(k2), k3:\(k3), n1:\(n1))")
        }
    }

    func testRowColorProperty_finalUp_probesMismatch_alwaysYellow() {
        // For any combination where final == .up and probes don't all agree → rowColor == .yellow
        var iterations = 0
        var attempts = 0
        while iterations < 100 && attempts < 10_000 {
            attempts += 1
            let (k1, k2, k3, n1) = randomProbeStatuses()
            let probes: Set<ProbeStatus> = [k1, k2, k3, n1]
            guard probes.count > 1 else { continue } // skip if all agree
            let item = MonitorItem.makeForTest(k1: k1, k2: k2, k3: k3, n1: n1, final: .up)
            XCTAssertEqual(item.rowColor, .yellow,
                "Expected .yellow when final == .up and probes mismatch (k1:\(k1), k2:\(k2), k3:\(k3), n1:\(n1))")
            iterations += 1
        }
        XCTAssertGreaterThanOrEqual(iterations, 100, "Could not generate 100 mismatch cases")
    }

    func testRowColorProperty_finalUp_probesAgree_alwaysGreen() {
        // For any combination where final == .up and all probes agree → rowColor == .green
        let allUpItem = MonitorItem.makeForTest(k1: .up, k2: .up, k3: .up, n1: .up, final: .up)
        XCTAssertEqual(allUpItem.rowColor, .green)

        let allDownItem = MonitorItem.makeForTest(k1: .down, k2: .down, k3: .down, n1: .down, final: .up)
        XCTAssertEqual(allDownItem.rowColor, .green)

        // 100 iterations: randomly pick either all .up or all .down for probes
        for _ in 0..<100 {
            let status: ProbeStatus = Bool.random() ? .up : .down
            let item = MonitorItem.makeForTest(k1: status, k2: status, k3: status, n1: status, final: .up)
            XCTAssertEqual(item.rowColor, .green,
                "Expected .green when final == .up and all probes agree on .\(status)")
        }
    }

    func testRowColorProperty_exhaustiveCombinations() {
        // Exhaustive check over all 2^5 = 32 combinations of (k1,k2,k3,n1,final)
        for k1 in ProbeStatus.allCases {
            for k2 in ProbeStatus.allCases {
                for k3 in ProbeStatus.allCases {
                    for n1 in ProbeStatus.allCases {
                        for finalStatus in ProbeStatus.allCases {
                            let item = MonitorItem.makeForTest(k1: k1, k2: k2, k3: k3, n1: n1, final: finalStatus)
                            if finalStatus == .down {
                                XCTAssertEqual(item.rowColor, .red)
                            } else {
                                let probes: Set<ProbeStatus> = [k1, k2, k3, n1]
                                if probes.count > 1 {
                                    XCTAssertEqual(item.rowColor, .yellow)
                                } else {
                                    XCTAssertEqual(item.rowColor, .green)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Property 5: Mapping completo dei campi monitor
    // Validates: Requirements 3.2

    func testFieldMappingProperty_allFieldsPreserved() {
        // For any MonitorItem created with random values, all fields must be preserved
        let names = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon",
                     "Zeta", "Eta", "Theta", "Iota", "Kappa"]
        let links: [String?] = [nil, "https://example.com", "https://monitor.local/status"]

        for i in 0..<100 {
            let name = names[i % names.count] + "_\(i)"
            let k1 = randomProbeStatus()
            let k2 = randomProbeStatus()
            let k3 = randomProbeStatus()
            let n1 = randomProbeStatus()
            let finalStatus = randomProbeStatus()
            let severity = Int.random(in: 0...2)
            let historyLength = Int.random(in: 0...20)
            let history = (0..<historyLength).map { _ in Int.random(in: 0...2) }
            let link = links[i % links.count]

            let item = MonitorItem.makeForTest(
                name: name,
                k1: k1, k2: k2, k3: k3, n1: n1,
                final: finalStatus,
                severity: severity,
                history: history,
                link: link
            )

            XCTAssertEqual(item.name, name, "name field not preserved at iteration \(i)")
            XCTAssertEqual(item.k1, k1, "k1 field not preserved at iteration \(i)")
            XCTAssertEqual(item.k2, k2, "k2 field not preserved at iteration \(i)")
            XCTAssertEqual(item.k3, k3, "k3 field not preserved at iteration \(i)")
            XCTAssertEqual(item.n1, n1, "n1 field not preserved at iteration \(i)")
            XCTAssertEqual(item.final, finalStatus, "final field not preserved at iteration \(i)")
            XCTAssertEqual(item.severity, severity, "severity field not preserved at iteration \(i)")
            XCTAssertEqual(item.history, history, "history field not preserved at iteration \(i)")
            XCTAssertEqual(item.link, link, "link field not preserved at iteration \(i)")
        }
    }

    func testFieldMappingProperty_linkNilPreserved() {
        // Verify nil link is preserved (not coerced to empty string or other value)
        for _ in 0..<100 {
            let item = MonitorItem.makeForTest(link: nil)
            XCTAssertNil(item.link, "nil link must remain nil after decoding")
        }
    }

    func testFieldMappingProperty_historyOrderPreserved() {
        // Verify history array order is preserved exactly
        for _ in 0..<100 {
            let history = (0..<Int.random(in: 1...30)).map { _ in Int.random(in: 0...2) }
            let item = MonitorItem.makeForTest(history: history)
            XCTAssertEqual(item.history, history, "history array order must be preserved")
        }
    }

    func testFieldMappingProperty_idIsUUID() {
        // Each MonitorItem must have a valid UUID id (generated locally)
        for _ in 0..<100 {
            let item = MonitorItem.makeForTest()
            // UUID() always produces a valid UUID; just verify it's not nil/zero
            XCTAssertNotEqual(item.id, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        }
    }
}
