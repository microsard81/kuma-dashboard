// Feature: ios-native-app, Property 12: Payload subscribe APNs contiene il token
// Feature: ios-native-app, Property 18: Validazione schema HTTPS
// Validates: Requirements 1.2, 1.6, 2.2, 3.1, 9.2, 9.4, 11.2, 12.3

import XCTest
@testable import UptimeDashboard

// MARK: - MockURLProtocol

/// Intercepts URLSession requests in tests without hitting the network.
final class MockURLProtocol: URLProtocol {

    /// Set this before each test to define the response for the next request.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Captures the last intercepted request for assertion.
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request

        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test helpers

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeClient(
    baseURL: URL = URL(string: "https://example.com")!,
    session: URLSession? = nil
) throws -> NetworkClient {
    let s = session ?? makeMockSession()
    return try NetworkClient(baseURL: baseURL, session: s)
}

private func makeHTTPResponse(
    url: URL = URL(string: "https://example.com")!,
    statusCode: Int,
    headers: [String: String] = [:]
) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
}

// MARK: - Random hex string generator

private func randomHexString(length: Int = 64) -> String {
    let hexChars = Array("0123456789abcdef")
    return String((0..<length).map { _ in hexChars.randomElement()! })
}

// MARK: - NetworkClientTests

final class NetworkClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.lastRequest = nil
    }

    // MARK: - Property 12: Payload subscribe APNs contiene il token
    // Validates: Requirements 9.2

    func testAPNsSubscribePayloadContainsToken() throws {
        // For any valid hex device_token, the POST /push/apns/subscribe request
        // must contain the device_token field unchanged in the JSON body.
        let session = makeMockSession()
        let client = try makeClient(session: session)

        for i in 0..<100 {
            let token = randomHexString(length: 64)
            let deviceId = UUID().uuidString

            MockURLProtocol.requestHandler = { request in
                let response = makeHTTPResponse(statusCode: 201)
                return (response, Data())
            }

            let expectation = XCTestExpectation(description: "subscribeAPNs iteration \(i)")

            Task {
                do {
                    try await client.subscribeAPNs(deviceToken: token, deviceId: deviceId)
                } catch {
                    XCTFail("subscribeAPNs threw unexpectedly at iteration \(i): \(error)")
                }

                // Verify the captured request body contains the token unchanged
                guard let capturedRequest = MockURLProtocol.lastRequest,
                      let bodyData = capturedRequest.httpBody else {
                    XCTFail("No request body captured at iteration \(i)")
                    expectation.fulfill()
                    return
                }

                guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: String] else {
                    XCTFail("Request body is not valid JSON at iteration \(i)")
                    expectation.fulfill()
                    return
                }

                XCTAssertEqual(
                    json["device_token"], token,
                    "device_token in body must equal the original token at iteration \(i)"
                )
                XCTAssertEqual(
                    json["device_id"], deviceId,
                    "device_id in body must equal the original deviceId at iteration \(i)"
                )

                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }

    // MARK: - Property 18: Validazione schema HTTPS
    // Validates: Requirements 12.3, 12.4

    func testHTTPSValidation() throws {
        // For any URL, only https:// must be accepted; all other schemes must throw insecureURL.
        let acceptedSchemes = ["https"]
        let rejectedSchemes = ["http", "ftp", "ws", "wss", "file", "data", "ssh", "telnet"]
        let host = "example.com"

        for _ in 0..<100 {
            // Pick a random scheme from the combined pool
            let allSchemes = acceptedSchemes + rejectedSchemes
            let scheme = allSchemes.randomElement()!
            let url = URL(string: "\(scheme)://\(host)")!

            if scheme == "https" {
                XCTAssertNoThrow(
                    try NetworkClient(baseURL: url, session: makeMockSession()),
                    "https:// must be accepted"
                )
            } else {
                XCTAssertThrowsError(
                    try NetworkClient(baseURL: url, session: makeMockSession()),
                    "\(scheme):// must be rejected"
                ) { error in
                    XCTAssertEqual(
                        error as? NetworkError, .insecureURL,
                        "Expected insecureURL for scheme \(scheme)"
                    )
                }
            }
        }
    }

    // MARK: - Unit Tests

    // MARK: testLogin401_returnsUnauthorized
    func testLogin401_returnsUnauthorized() async throws {
        MockURLProtocol.requestHandler = { _ in
            let response = makeHTTPResponse(statusCode: 401)
            return (response, Data())
        }

        let client = try makeClient()

        do {
            _ = try await client.login(username: "user", password: "wrong")
            XCTFail("Expected unauthorized error")
        } catch NetworkError.unauthorized {
            // expected
        }
    }

    // MARK: testLoginSuccess_returnsSuccess
    func testLoginSuccess_returnsSuccess() async throws {
        // Flask returns 200 when login succeeds without redirect (or redirect to /)
        MockURLProtocol.requestHandler = { _ in
            let response = makeHTTPResponse(statusCode: 200)
            return (response, Data())
        }

        let client = try makeClient()
        let result = try await client.login(username: "user", password: "correct")
        XCTAssertEqual(result, .success)
    }

    // MARK: testVerify2FA_success
    func testVerify2FA_success() async throws {
        MockURLProtocol.requestHandler = { _ in
            let response = makeHTTPResponse(statusCode: 200)
            return (response, Data())
        }

        let client = try makeClient()
        let result = try await client.verify2FA(code: "123456")
        XCTAssertTrue(result)
    }

    // MARK: testVerify2FA_error
    func testVerify2FA_error() async throws {
        MockURLProtocol.requestHandler = { _ in
            let response = makeHTTPResponse(statusCode: 200)
            return (response, Data())
        }

        let client = try makeClient()
        // A wrong code still returns 200 from Flask (re-renders the form),
        // so verify2FA returns true for status 200. Test that a network error propagates.
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await client.verify2FA(code: "000000")
            XCTFail("Expected networkError")
        } catch NetworkError.networkError {
            // expected
        }
    }

    // MARK: testSessionExpired_redirectToLogin
    func testSessionExpired_redirectToLogin() async throws {
        // fetchDashboardData should throw sessionExpired when Flask redirects to /login
        MockURLProtocol.requestHandler = { _ in
            let response = makeHTTPResponse(
                statusCode: 302,
                headers: ["Location": "https://example.com/login"]
            )
            return (response, Data())
        }

        let client = try makeClient()

        var receivedNotification = false
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("sessionExpired"),
            object: nil,
            queue: .main
        ) { _ in receivedNotification = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        do {
            _ = try await client.fetchDashboardData()
            XCTFail("Expected sessionExpired error")
        } catch NetworkError.sessionExpired {
            // expected
        }

        // Give the notification a moment to be posted
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(receivedNotification, "sessionExpired notification must be posted")
    }

    // MARK: testFetchDashboardData_success
    func testFetchDashboardData_success() async throws {
        let json = """
        {
            "items": [
                {
                    "name": "Service A",
                    "k1": "UP", "k2": "UP", "k3": "UP", "n1": "UP",
                    "final": "UP",
                    "severity": 0,
                    "history": [0, 0, 1],
                    "link": null
                }
            ],
            "global_state": "GREEN",
            "timestamp": "2024-01-15T10:30:00"
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { _ in
            let response = makeHTTPResponse(statusCode: 200)
            return (response, json)
        }

        let client = try makeClient()
        let dashboard = try await client.fetchDashboardData()

        XCTAssertEqual(dashboard.globalState, .green)
        XCTAssertEqual(dashboard.items.count, 1)
        XCTAssertEqual(dashboard.items[0].name, "Service A")
        XCTAssertEqual(dashboard.items[0].final, .up)
    }
}
