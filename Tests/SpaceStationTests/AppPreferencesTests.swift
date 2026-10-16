import XCTest

final class AppPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SpaceStationPrefsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsMatchTheDesign() {
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs.menuBarDisplay, .iconAndName)
        XCTAssertTrue(prefs.shortenMenuBarNames)
        XCTAssertEqual(prefs.hotCorner, .off)
        XCTAssertEqual(prefs.hotCornerDelay, AppPreferences.instantDelay)   // "Instant", per the product owner
        XCTAssertEqual(prefs.panelPlacement, .centered)   // opens centred, as it always did; next-to-corner is opt-in
        XCTAssertTrue(prefs.showKeyboardHints)
        XCTAssertFalse(prefs.closeOnPointerExit)
        XCTAssertEqual(prefs.switcherShortcut?.display, "⌃⌥S")
    }

    func testValuesPersistAcrossInstances() {
        let prefs = AppPreferences(defaults: defaults)
        prefs.menuBarDisplay = .nameOnly
        prefs.shortenMenuBarNames = false
        prefs.hotCorner = .topRight
        prefs.hotCornerDelay = 0.4
        prefs.panelPlacement = .nearCorner
        prefs.showKeyboardHints = false
        prefs.closeOnPointerExit = true
        prefs.switcherShortcut = KeyBinding(keyCode: 46, flags: .maskCommand)

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.menuBarDisplay, .nameOnly)
        XCTAssertFalse(reloaded.shortenMenuBarNames)
        XCTAssertEqual(reloaded.hotCorner, .topRight)
        XCTAssertEqual(reloaded.hotCornerDelay, 0.4)
        XCTAssertEqual(reloaded.panelPlacement, .nearCorner)
        XCTAssertFalse(reloaded.showKeyboardHints)
        XCTAssertTrue(reloaded.closeOnPointerExit)
        XCTAssertEqual(reloaded.switcherShortcut?.display, "⌘M")
    }

    func testTheShortcutCanBeTurnedOffAndStaysOff() {
        let prefs = AppPreferences(defaults: defaults)
        prefs.switcherShortcut = nil
        XCTAssertNil(AppPreferences(defaults: defaults).switcherShortcut)
    }

    func testDelayIsClampedToItsRange() {
        let prefs = AppPreferences(defaults: defaults)
        prefs.hotCornerDelay = 0
        XCTAssertEqual(prefs.hotCornerDelay, AppPreferences.delayRange.lowerBound)
        prefs.hotCornerDelay = 5
        XCTAssertEqual(prefs.hotCornerDelay, AppPreferences.delayRange.upperBound)
        defaults.set(99.0, forKey: AppPreferences.Key.hotCornerDelay)
        XCTAssertEqual(AppPreferences(defaults: defaults).hotCornerDelay, AppPreferences.delayRange.upperBound)
    }

    func testExistingControlSInstallKeepsControlS() {
        // Someone who ran the pre-redesign build with the switcher hotkey enabled.
        defaults.set(true, forKey: AppPreferences.Key.legacyHotKeyEnabled)
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs.switcherShortcut?.display, "⌃S")
        XCTAssertNil(defaults.object(forKey: AppPreferences.Key.legacyHotKeyEnabled), "legacy key is cleaned up")
        XCTAssertEqual(AppPreferences(defaults: defaults).switcherShortcut?.display, "⌃S", "migration is stored")
    }

    func testExistingInstallThatTurnedTheHotkeyOffStaysOff() {
        defaults.set(false, forKey: AppPreferences.Key.legacyHotKeyEnabled)
        XCTAssertNil(AppPreferences(defaults: defaults).switcherShortcut)
    }

    func testCorruptStoredValuesFallBackSafely() {
        defaults.set("garbage", forKey: AppPreferences.Key.menuBarDisplay)
        defaults.set("nowhere", forKey: AppPreferences.Key.hotCorner)
        defaults.set("not a binding", forKey: AppPreferences.Key.switcherShortcut)
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs.menuBarDisplay, .iconAndName)
        XCTAssertEqual(prefs.hotCorner, .off)
        XCTAssertEqual(prefs.switcherShortcut?.display, "⌃⌥S")
    }

    func testTheSavedCornerKeyIsUnchangedFromEarlierBuilds() {
        defaults.set("topRight", forKey: "switcherHotCorner")
        XCTAssertEqual(AppPreferences(defaults: defaults).hotCorner, .topRight)
    }
}
