import XCTest

final class UpdateVersionTests: XCTestCase {
    func testComponents() {
        XCTAssertEqual(UpdateVersion.components("1.2.3"), [1, 2, 3])
        XCTAssertEqual(UpdateVersion.components("v1.2.3"), [1, 2, 3])
        XCTAssertEqual(UpdateVersion.components("V2.0"), [2, 0])
        XCTAssertEqual(UpdateVersion.components("v1.2.3-beta.1"), [1, 2, 3])
        XCTAssertEqual(UpdateVersion.components(" 10 "), [10])
        XCTAssertNil(UpdateVersion.components("latest"))
        XCTAssertNil(UpdateVersion.components(""))
        XCTAssertNil(UpdateVersion.components("v..1"))
    }

    func testNewerVersionsAreDetectedNumerically() {
        XCTAssertTrue(UpdateVersion.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(UpdateVersion.isNewer("v1.1.0", than: "1.0.9"))
        XCTAssertTrue(UpdateVersion.isNewer("2.0", than: "1.9.9"))
        XCTAssertTrue(UpdateVersion.isNewer("1.10.0", than: "1.9.0"), "numeric, not string, comparison")
        XCTAssertTrue(UpdateVersion.isNewer("1.0.0.1", than: "1.0.0"))
    }

    func testSameOrOlderIsNotNewer() {
        XCTAssertFalse(UpdateVersion.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(UpdateVersion.isNewer("v1.0", than: "1.0.0"), "missing parts count as zero")
        XCTAssertFalse(UpdateVersion.isNewer("0.9.9", than: "1.0.0"))
        XCTAssertFalse(UpdateVersion.isNewer("1.9.0", than: "1.10.0"))
    }

    func testPreReleaseRules() {
        XCTAssertTrue(UpdateVersion.isNewer("1.0.0", than: "1.0.0-beta"), "the final release replaces the beta")
        XCTAssertFalse(UpdateVersion.isNewer("1.0.0-beta", than: "1.0.0"))
        XCTAssertFalse(UpdateVersion.isNewer("1.0.0-beta", than: "1.0.0-beta"))
    }

    func testUnparseableVersionsAreNeverNewer() {
        XCTAssertFalse(UpdateVersion.isNewer("nightly", than: "1.0.0"))
        XCTAssertFalse(UpdateVersion.isNewer("1.0.0", than: "unknown"))
    }
}

final class ReleaseParsingTests: XCTestCase {
    private func json(tag: String = "v1.2.0", url: String = "https://github.com/gregorycarter/SpaceStation/releases/tag/v1.2.0",
                      name: String? = "SpaceStation 1.2.0", draft: Bool = false, prerelease: Bool = false) -> Data {
        var object: [String: Any] = ["tag_name": tag, "html_url": url, "draft": draft, "prerelease": prerelease, "id": 1]
        if let name { object["name"] = name }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    func testParsesATypicalRelease() throws {
        let release = try XCTUnwrap(UpdateChecker.parseRelease(json()))
        XCTAssertEqual(release.tag, "v1.2.0")
        XCTAssertEqual(release.version, "1.2.0")
        XCTAssertEqual(release.name, "SpaceStation 1.2.0")
        XCTAssertEqual(release.url.absoluteString, "https://github.com/gregorycarter/SpaceStation/releases/tag/v1.2.0")
    }

    func testDraftsAndPreReleasesAreIgnored() {
        XCTAssertNil(UpdateChecker.parseRelease(json(draft: true)))
        XCTAssertNil(UpdateChecker.parseRelease(json(prerelease: true)))
    }

    func testAMissingNameFallsBackToTheVersion() throws {
        XCTAssertEqual(try XCTUnwrap(UpdateChecker.parseRelease(json(name: nil))).name, "SpaceStation 1.2.0")
    }

    func testAnUnparseableTagOrBodyIsRejected() {
        XCTAssertNil(UpdateChecker.parseRelease(json(tag: "latest")))
        XCTAssertNil(UpdateChecker.parseRelease(Data("not json".utf8)))
        XCTAssertNil(UpdateChecker.parseRelease(Data("{}".utf8)))
    }

    func testOnlyReleasePagesOnThisRepositoryAreTrusted() {
        let trusted = ["https://github.com/gregorycarter/SpaceStation/releases/tag/v1.0.0",
                       "https://github.com/GregoryCarter/spacestation/releases"]
        let untrusted = ["http://github.com/gregorycarter/SpaceStation/releases",          // not https
                         "https://evil.example.com/gregorycarter/SpaceStation/releases",
                         "https://github.com.evil.example/gregorycarter/SpaceStation/",
                         "https://github.com/someone-else/SpaceStation/releases",
                         "https://github.com/gregorycarter/SpaceStation-fake/releases",
                         "https://api.github.com/gregorycarter/SpaceStation/"]
        for string in trusted { XCTAssertTrue(UpdateChecker.isTrustedReleaseURL(URL(string: string)!), string) }
        for string in untrusted { XCTAssertFalse(UpdateChecker.isTrustedReleaseURL(URL(string: string)!), string) }
    }

    func testAnUntrustedLinkInTheResponseIsReplacedByTheReleasesPage() throws {
        let release = try XCTUnwrap(UpdateChecker.parseRelease(json(url: "https://evil.example.com/download.dmg")))
        XCTAssertEqual(release.url, UpdateChecker.releasesPage)
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var calls = 0
    private var requests: [URLRequest] = []

    override func setUp() async throws {
        suiteName = "SpaceStationUpdateTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        calls = 0
        requests = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func response(_ status: Int) -> URLResponse {
        HTTPURLResponse(url: UpdateChecker.latestReleaseURL, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private func release(_ tag: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "html_url": "https://github.com/gregorycarter/SpaceStation/releases/tag/\(tag)", "name": "SpaceStation \(tag)",
        ])
    }

    private func checker(current: String = "1.0.0", now: @escaping () -> Date = Date.init,
                         respond: @escaping () throws -> (Data, URLResponse)) -> UpdateChecker {
        UpdateChecker(currentVersion: current, defaults: defaults, now: now, fetch: { [unowned self] request in
            calls += 1
            requests.append(request)
            return try respond()
        })
    }

    func testANewerReleaseIsAvailable() async throws {
        let c = checker { (self.release("v1.1.0"), self.response(200)) }
        let status = await c.check()
        guard case .available(let info) = status else { return XCTFail("expected available, got \(status)") }
        XCTAssertEqual(info.version, "1.1.0")
        XCTAssertEqual(c.availableUpdate, info)
    }

    func testTheSameVersionIsUpToDate() async {
        let c = checker { (self.release("v1.0.0"), self.response(200)) }
        let status = await c.check()
        XCTAssertEqual(status, .upToDate(currentVersion: "1.0.0"))
        XCTAssertNil(c.availableUpdate)
    }

    func testNoReleasesYet() async {
        let c = checker { (Data(), self.response(404)) }
        let status = await c.check()
        XCTAssertEqual(status, .noReleases)
    }

    func testFailuresAreReportedPlainly() async {
        var c = checker { (Data(), self.response(500)) }
        var status = await c.check()
        XCTAssertEqual(status, .failed("GitHub returned an error (500)."))

        c = checker { (Data(), self.response(403)) }
        status = await c.check()
        XCTAssertEqual(status, .failed("GitHub is limiting requests right now. Try again later."))

        c = checker { throw URLError(.notConnectedToInternet) }
        status = await c.check()
        XCTAssertEqual(status, .failed("Couldn't reach GitHub. Check your connection and try again."))

        c = checker { (Data("garbage".utf8), self.response(200)) }
        status = await c.check()
        XCTAssertEqual(status, .failed("Couldn't read GitHub's response."))
    }

    func testAFoundUpdateIsClearedByALaterUpToDateResult() async {
        var tag = "v1.1.0"
        let c = checker { (self.release(tag), self.response(200)) }
        _ = await c.check()
        XCTAssertNotNil(c.availableUpdate)
        tag = "v1.0.0"
        _ = await c.check()
        XCTAssertNil(c.availableUpdate)
    }

    func testTheRequestIsAnonymousAndGoesToGitHubOverHTTPS() async throws {
        let c = checker { (self.release("v1.0.0"), self.response(200)) }
        _ = await c.check()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "api.github.com")
        XCTAssertEqual(request.httpMethod ?? "GET", "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "SpaceStation/1.0.0")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.httpBody)
    }

    func testAutomaticChecksDoNothingUnlessEnabled() async {
        let c = checker { (self.release("v9.0.0"), self.response(200)) }
        await c.checkAutomaticallyIfDue(enabled: false)
        XCTAssertEqual(calls, 0, "no network use unless the user turned automatic checks on")
        XCTAssertNil(c.status)
    }

    func testAutomaticChecksAreThrottledToOncePerDay() async {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let c = checker(now: { clock }) { (self.release("v1.0.0"), self.response(200)) }
        await c.checkAutomaticallyIfDue(enabled: true)
        XCTAssertEqual(calls, 1)

        clock = clock.addingTimeInterval(23 * 3600)
        await c.checkAutomaticallyIfDue(enabled: true)
        XCTAssertEqual(calls, 1, "within 24 hours")

        clock = clock.addingTimeInterval(2 * 3600)
        await c.checkAutomaticallyIfDue(enabled: true)
        XCTAssertEqual(calls, 2, "more than 24 hours since the last check")
    }

    func testAManualCheckIgnoresTheThrottle() async {
        let c = checker { (self.release("v1.0.0"), self.response(200)) }
        await c.checkAutomaticallyIfDue(enabled: true)
        _ = await c.check()
        _ = await c.check()
        XCTAssertEqual(calls, 3)
    }

    func testAFailedAutomaticCheckIsRetriedNextTime() async {
        var fail = true
        let c = checker { fail ? (Data(), self.response(500)) : (self.release("v1.0.0"), self.response(200)) }
        await c.checkAutomaticallyIfDue(enabled: true)
        XCTAssertEqual(calls, 1)
        fail = false
        await c.checkAutomaticallyIfDue(enabled: true)
        XCTAssertEqual(calls, 2, "a failed check doesn't start the 24-hour wait")
    }
}

final class UpdateStatusSummaryTests: XCTestCase {
    func testSummaries() {
        XCTAssertEqual(UpdateStatus.upToDate(currentVersion: "1.0.0").summary, "SpaceStation 1.0.0 is up to date.")
        let release = ReleaseInfo(tag: "v1.1.0", version: "1.1.0", name: "n", url: UpdateChecker.releasesPage)
        XCTAssertEqual(UpdateStatus.available(release).summary, "Version 1.1.0 is available.")
        XCTAssertEqual(UpdateStatus.noReleases.summary, "No releases have been published yet.")
        XCTAssertEqual(UpdateStatus.failed("Nope").summary, "Nope")
    }
}
