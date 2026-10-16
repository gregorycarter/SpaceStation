import XCTest
import AppKit

/// Builds the menu without installing a status item, against the real Space state of the machine
/// running the tests, so these check structure and invariants rather than particular names.
@MainActor
final class StatusItemMenuTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var names: SpaceNameManager!
    private var prefs: AppPreferences!
    private var tracker: SpaceTracker!
    private var controller: StatusItemController!

    override func setUp() async throws {
        suiteName = "SpaceStationMenuTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        names = SpaceNameManager(defaults: defaults)
        prefs = AppPreferences(defaults: defaults)
        tracker = SpaceTracker()
        let noop = StatusItemController.Actions(
            rename: { _ in }, showSwitcher: {}, showSettings: {}, showAbout: {}, allowAccessibility: {}, handleSwitchOutcome: { _ in })
        controller = StatusItemController(spaceTracker: tracker, nameManager: names, preferences: prefs,
                                          actions: noop, installStatusItem: false)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        controller.populate(menu)
        return menu
    }

    func testEverySpaceHasARowAndAHiddenRenameAlternate() {
        let items = menu().items
        let primaries = items.filter { $0.action == NSSelectorFromString("chooseSpace:") }
        let alternates = items.filter { $0.isAlternate }
        XCTAssertEqual(primaries.count, tracker.spaces.count)
        XCTAssertEqual(alternates.count, tracker.spaces.count)
        for alternate in alternates {
            XCTAssertTrue(alternate.title.hasPrefix("Rename “") && alternate.title.hasSuffix("”…"))
        }
    }

    func testRowsShowTheCustomNameAndIcon() throws {
        let space = try XCTUnwrap(tracker.spaces.first)
        names.setName("Inbox", for: space)
        names.setIcon(.symbol("tray"), for: space)
        let row = try XCTUnwrap(menu().items.first { $0.title == "Inbox" })
        XCTAssertNotNil(row.image)
        let alternate = try XCTUnwrap(menu().items.first { $0.title == "Rename “Inbox”…" })
        XCTAssertTrue(alternate.isAlternate)
    }

    func testAtMostOneRowIsChecked() {
        let checked = menu().items.filter { $0.state == .on }
        XCTAssertLessThanOrEqual(checked.count, 1)
        XCTAssertEqual(checked.isEmpty, tracker.isInFullscreenSpace)
    }

    func testStructureAroundTheSpaceRows() throws {
        let items = menu().items
        let spacesHeader = try XCTUnwrap(items.first { $0.title == "Spaces" })
        XCTAssertFalse(spacesHeader.isEnabled)
        for title in ["Show Switcher", "Settings…", "About SpaceStation", "Quit SpaceStation"] {
            XCTAssertNotNil(items.first { $0.title == title }, "missing \(title)")
        }
        XCTAssertEqual(items.first { $0.title == "Settings…" }?.keyEquivalent, ",")
        XCTAssertEqual(items.first { $0.title == "Quit SpaceStation" }?.keyEquivalent, "q")
        XCTAssertEqual(items.filter(\.isSeparatorItem).count >= 2, true)
    }

    func testRenameCurrentNamesTheSpaceUnlessFullscreen() throws {
        let rename = try XCTUnwrap(menu().items.first { $0.title.hasPrefix("Rename") && !$0.isAlternate })
        if tracker.isInFullscreenSpace {
            XCTAssertEqual(rename.title, "Rename Space…")
            XCTAssertFalse(rename.isEnabled)
        } else {
            XCTAssertEqual(rename.title, "Rename “\(names.name(for: tracker.currentSpace))”…")
        }
    }

    func testShowSwitcherDisplaysTheRecordedShortcut() throws {
        prefs.switcherShortcut = KeyBinding(keyCode: 1, flags: CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue))
        let item = try XCTUnwrap(menu().items.first { $0.title == "Show Switcher" })
        XCTAssertEqual(item.keyEquivalent, "s")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.control, .option])

        prefs.switcherShortcut = nil
        let off = try XCTUnwrap(menu().items.first { $0.title == "Show Switcher" })
        XCTAssertEqual(off.keyEquivalent, "")
    }

    func testAccessibilityItemAppearsOnlyWhenPermissionIsMissing() {
        let hasItem = menu().items.contains { $0.title.hasPrefix("Allow Accessibility") }
        XCTAssertEqual(hasItem, !tracker.hasAccessibilityPermission)
    }

    func testModifierMaskConversion() {
        let all = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
                               | CGEventFlags.maskShift.rawValue | CGEventFlags.maskCommand.rawValue | CGEventFlags.maskSecondaryFn.rawValue)
        XCTAssertEqual(StatusItemController.modifierMask(for: all), [.control, .option, .shift, .command])
        XCTAssertEqual(StatusItemController.modifierMask(for: .maskControl), [.control])
        XCTAssertEqual(StatusItemController.modifierMask(for: []), [])
    }
}

final class SpaceIconImageTests: XCTestCase {
    func testSymbolImagesAreTemplates() {
        let image = SpaceIconImage.image(for: .symbol("tray"), index: 1)
        XCTAssertTrue(image.isTemplate)
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testAnUnknownSymbolFallsBackToTheNumberSquare() {
        let fallback = SpaceIconImage.image(for: .symbol("definitely.not.a.symbol"), index: 3)
        XCTAssertGreaterThan(fallback.size.width, 0)
        XCTAssertTrue(fallback.isTemplate)
    }

    func testEmojiImagesAreColourAtTheRequestedSize() {
        let image = SpaceIconImage.image(for: .emoji("🔥"), index: 1, size: 16)
        XCTAssertFalse(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 16, height: 16))
    }

    func testNoIconShowsTheNumber() {
        let image = SpaceIconImage.image(for: nil, index: 7)
        XCTAssertTrue(image.isTemplate)
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testFullscreenSymbolExists() {
        XCTAssertNotNil(SpaceIconImage.symbol(SpaceIconImage.fullscreenSymbol))
    }
}
