import XCTest

@MainActor
final class AccessibilityControllerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "SpaceStationAccessibilityTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }

    func testCheckAndRequestUseDifferentPromptOptionsAndRememberTrust() {
        var prompts: [Bool] = []
        let controller = AccessibilityController(defaults: defaults, system: .init(
            identity: { .init(isAdHoc: true, requirement: "current") },
            isTrusted: { prompts.append($0); return $0 }, reset: {}, sleep: { _ in }, openSettings: {}))
        controller.check()
        XCTAssertFalse(controller.isTrusted)
        XCTAssertEqual(controller.hint, .adHocBuild)
        controller.request()
        XCTAssertEqual(prompts, [false, true])
        XCTAssertTrue(controller.isTrusted)
        XCTAssertNil(controller.hint)
        XCTAssertEqual(defaults.string(forKey: AccessibilityController.lastTrustedRequirementKey), "current")
    }

    func testOpeningSettingsPromptsWithoutChangingPublishedState() {
        var prompted = false
        var opened = false
        let controller = AccessibilityController(defaults: defaults, system: .init(
            identity: { nil }, isTrusted: { prompted = $0; return true },
            reset: {}, sleep: { _ in }, openSettings: { opened = true }))
        controller.openSettings()
        XCTAssertTrue(prompted)
        XCTAssertTrue(opened)
        XCTAssertFalse(controller.isTrusted, "the existing UI refreshes this on its next check")
    }

    func testResetWaitsBeforeRequestingAndOpeningSettingsEvenIfResetFails() async {
        var events: [String] = []
        let controller = AccessibilityController(defaults: defaults, system: .init(
            identity: { nil }, isTrusted: { events.append("prompt:\($0)"); return true },
            reset: { events.append("reset"); throw CocoaError(.fileReadUnknown) },
            sleep: { events.append("sleep:\($0)") }, openSettings: { events.append("settings") }))
        await controller.resetAndRequest().value
        XCTAssertEqual(events, ["reset", "sleep:500000000", "prompt:true", "settings"])
        XCTAssertTrue(controller.isTrusted)
    }

    func testResetAfterAlreadyPromptingRelaunchesInsteadOfPromptingAgain() async {
        var events: [String] = []
        let controller = AccessibilityController(defaults: defaults, system: .init(
            identity: { nil }, isTrusted: { events.append("prompt:\($0)"); return false },
            reset: { events.append("reset") }, sleep: { _ in }, openSettings: { events.append("settings") },
            relaunchToRequest: { events.append("relaunch") }))
        controller.request()
        await controller.resetAndRequest().value
        XCTAssertEqual(events, ["prompt:true", "reset", "relaunch"],
                       "macOS only lists an app for a process's first prompt, so a reset needs a fresh process")
    }

    func testAutomaticRecoveryIsRecordedOnceAndDoesNotOpenSettings() async {
        defaults.set("previous", forKey: AccessibilityController.lastTrustedRequirementKey)
        var resets = 0
        let reset = expectation(description: "injected reset")
        let controller = AccessibilityController(defaults: defaults, system: .init(
            identity: { .init(isAdHoc: true, requirement: "current") }, isTrusted: { _ in false },
            reset: { resets += 1; reset.fulfill() }, sleep: { _ in },
            openSettings: { XCTFail("automatic recovery must not open Settings") }))
        controller.check()
        XCTAssertEqual(controller.hint, .signatureChanged)
        controller.healStaleGrantIfNeeded()
        controller.healStaleGrantIfNeeded()
        await fulfillment(of: [reset], timeout: 1)
        XCTAssertEqual(resets, 1)
        XCTAssertEqual(defaults.string(forKey: AccessibilityController.lastAutoResetRequirementKey), "current")
    }
}
