import XCTest

@MainActor
final class UpdateConcurrencyTests: XCTestCase {
    @MainActor
    private final class DeferredFetch {
        var calls = 0
        var onRequest: (() -> Void)?
        private var pending: [CheckedContinuation<(Data, URLResponse), Error>] = []

        func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
            calls += 1
            return try await withCheckedThrowingContinuation {
                pending.append($0)
                let notify = onRequest
                onRequest = nil
                notify?()
            }
        }

        func complete(version: String) {
            let body = Data("{\"tag_name\":\"v\(version)\",\"html_url\":\"https://github.com/gregorycarter/SpaceStation/releases\"}".utf8)
            let response = HTTPURLResponse(url: UpdateChecker.latestReleaseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let requests = pending
            pending.removeAll()
            for request in requests { request.resume(returning: (body, response)) }
        }

        func fail() {
            let requests = pending
            pending.removeAll()
            for request in requests { request.resume(throwing: URLError(.notConnectedToInternet)) }
        }
    }

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "SpaceStationUpdateConcurrencyTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }

    func testConcurrentInitialChecksShareOneRequestAndRemainChecking() async {
        let fetch = DeferredFetch()
        let started = expectation(description: "request started")
        fetch.onRequest = { started.fulfill() }
        let checker = UpdateChecker(currentVersion: "1.0.0", defaults: defaults, fetch: fetch.fetch)
        let first = Task { await checker.check() }
        await fulfillment(of: [started], timeout: 1)

        let joined = expectation(description: "second caller joined")
        let second = Task { joined.fulfill(); return await checker.check() }
        await fulfillment(of: [joined], timeout: 1)
        XCTAssertEqual(fetch.calls, 1)
        XCTAssertTrue(checker.isChecking)
        XCTAssertNil(checker.status)

        fetch.complete(version: "2.0.0")
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult, secondResult)
        XCTAssertEqual(checker.availableUpdate?.version, "2.0.0")
        XCTAssertFalse(checker.isChecking)
    }

    func testManualCheckJoinsAutomaticRefreshInsteadOfReturningOldStatus() async {
        let fetch = DeferredFetch()
        let initialStarted = expectation(description: "initial request")
        fetch.onRequest = { initialStarted.fulfill() }
        var now = Date(timeIntervalSince1970: 100_000)
        let checker = UpdateChecker(currentVersion: "1.0.0", defaults: defaults, now: { now }, fetch: fetch.fetch)
        let initial = Task { await checker.check() }
        await fulfillment(of: [initialStarted], timeout: 1)
        fetch.complete(version: "1.0.0")
        _ = await initial.value

        now = now.addingTimeInterval(UpdateChecker.automaticInterval)
        let refreshStarted = expectation(description: "automatic refresh")
        fetch.onRequest = { refreshStarted.fulfill() }
        let automatic = Task { await checker.checkAutomaticallyIfDue(enabled: true) }
        await fulfillment(of: [refreshStarted], timeout: 1)
        let joined = expectation(description: "manual caller joined")
        var manualReturned = false
        let manual = Task {
            joined.fulfill()
            let result = await checker.check()
            manualReturned = true
            return result
        }
        await fulfillment(of: [joined], timeout: 1)
        XCTAssertFalse(manualReturned, "must await the fresh result")
        XCTAssertTrue(checker.isChecking)
        XCTAssertEqual(fetch.calls, 2)
        fetch.complete(version: "2.0.0")
        let result = await manual.value
        await automatic.value
        guard case .available(let release) = result else { return XCTFail("expected the fresh update") }
        XCTAssertEqual(release.version, "2.0.0")
        XCTAssertEqual(defaults.object(forKey: UpdateChecker.lastCheckKey) as? Date, now)
    }

    func testFailureClearsTheInFlightTaskSoAnotherCheckCanRetry() async {
        let fetch = DeferredFetch()
        let started = expectation(description: "failed request")
        fetch.onRequest = { started.fulfill() }
        let checker = UpdateChecker(currentVersion: "1.0.0", defaults: defaults, fetch: fetch.fetch)
        let first = Task { await checker.check() }
        await fulfillment(of: [started], timeout: 1)
        fetch.fail()
        _ = await first.value
        XCTAssertFalse(checker.isChecking)
        XCTAssertNil(defaults.object(forKey: UpdateChecker.lastCheckKey))

        let retryStarted = expectation(description: "retry")
        fetch.onRequest = { retryStarted.fulfill() }
        let retry = Task { await checker.check() }
        await fulfillment(of: [retryStarted], timeout: 1)
        fetch.complete(version: "2.0.0")
        _ = await retry.value
        XCTAssertEqual(fetch.calls, 2)
        XCTAssertEqual(checker.availableUpdate?.version, "2.0.0")
        XCTAssertFalse(checker.isChecking)
    }
}
