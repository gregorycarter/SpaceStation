import XCTest
import AppKit

/// Builds menus from fixtures; no WindowServer, permission checks, or real preferences are used.
@MainActor
final class StatusItemMenuTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var names: SpaceNameManager!
    private var prefs: AppPreferences!
    private var spaces: [SpaceInfo] = []
    private var currentIndex = 1
    private var isFullscreen = false
    private var hasAccessibility = true
    private var hotkeys: [String: Any]?
    private let target = NSObject()
    private var updates: UpdateChecker!

    override func setUp() async throws {
        suiteName = "SpaceStationMenuTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        names = SpaceNameManager(defaults: defaults)
        prefs = AppPreferences(defaults: defaults)
        spaces = [SpaceInfo(id: "first", index: 1), SpaceInfo(id: "second", index: 2), SpaceInfo(id: "third", index: 3)]
        currentIndex = 2
        isFullscreen = false
        hasAccessibility = true
        hotkeys = nil
        updates = UpdateChecker(currentVersion: "1.0.0", defaults: defaults, fetch: { _ in
            let body = try JSONSerialization.data(withJSONObject: [
                "tag_name": "v1.5.0", "html_url": "https://github.com/gregorycarter/SpaceStation/releases/tag/v1.5.0"])
            return (body, HTTPURLResponse(url: UpdateChecker.latestReleaseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        let current = spaces.first { $0.index == currentIndex } ?? spaces.first ?? .placeholder
        let snapshot = StatusMenuSnapshot(
            items: spaces.map {
                StatusMenuSnapshot.Item(space: $0, name: names.name(for: $0), icon: names.icon(for: $0),
                                        shortcut: SystemShortcuts.switchToDesktop($0.index, in: hotkeys))
            },
            currentSpace: current, currentName: names.name(for: current), isInFullscreenSpace: isFullscreen,
            hasAccessibilityPermission: hasAccessibility, switcherShortcut: prefs.switcherShortcut,
            update: updates.availableUpdate)
        StatusItemController.populate(menu, snapshot: snapshot, target: target)
        return menu
    }

    func testEverySpaceHasARowAndAHiddenRenameAlternate() {
        let items = menu().items
        let primaries = items.filter { $0.action == NSSelectorFromString("chooseSpace:") }
        let alternates = items.filter { $0.isAlternate }
        XCTAssertEqual(primaries.count, spaces.count)
        XCTAssertEqual(alternates.count, spaces.count)
        for alternate in alternates {
            XCTAssertTrue(alternate.title.hasPrefix("Rename “") && alternate.title.hasSuffix("”…"))
        }
    }

    func testRowsShowTheCustomNameAndIcon() throws {
        let space = try XCTUnwrap(spaces.first)
        names.setName("Inbox", for: space)
        names.setIcon(.symbol("tray"), for: space)
        let row = try XCTUnwrap(menu().items.first { $0.title == "Inbox" })
        XCTAssertNotNil(row.image)
        let alternate = try XCTUnwrap(menu().items.first { $0.title == "Rename “Inbox”…" })
        XCTAssertTrue(alternate.isAlternate)
    }

    func testOnlyTheCurrentDesktopIsChecked() {
        let checked = menu().items.filter { $0.state == .on }
        XCTAssertEqual(checked.count, 1)
        XCTAssertEqual((checked.first?.representedObject as? SpaceInfo)?.id, "second")
    }

    func testFullscreenHasNoCheckedDesktopAndDisablesRename() throws {
        isFullscreen = true
        XCTAssertTrue(menu().items.allSatisfy { $0.state == .off })
        let rename = try XCTUnwrap(menu().items.first { $0.title == "Rename Space…" })
        XCTAssertFalse(rename.isEnabled)
    }

    func testPlaceholderDisablesRename() throws {
        spaces = [.placeholder]
        let rename = try XCTUnwrap(menu().items.first { $0.title.hasPrefix("Rename") && !$0.isAlternate })
        XCTAssertFalse(rename.isEnabled)
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

    func testRenameCurrentUsesTheCurrentName() throws {
        names.setName("Work", for: spaces[1])
        let rename = try XCTUnwrap(menu().items.first { $0.title.hasPrefix("Rename") && !$0.isAlternate })
        XCTAssertEqual(rename.title, "Rename “Work”…")
        XCTAssertTrue(rename.isEnabled)
    }

    func testRemappedShortcutAndOptionAlternate() throws {
        hotkeys = ["AppleSymbolicHotKeys": [
            "119": ["enabled": 1, "value": ["parameters": [65535, 46, Int(CGEventFlags.maskCommand.rawValue)]]]
        ]]
        let items = menu().items
        let primary = try XCTUnwrap(items.first { ($0.representedObject as? SpaceInfo)?.id == "second" && !$0.isAlternate })
        let alternate = try XCTUnwrap(items.first { ($0.representedObject as? SpaceInfo)?.id == "second" && $0.isAlternate })
        XCTAssertEqual(primary.keyEquivalent, "m")
        XCTAssertEqual(primary.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(alternate.keyEquivalent, "m")
        XCTAssertEqual(alternate.keyEquivalentModifierMask, [.command, .option])
        XCTAssertTrue(primary.target === target)
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
        XCTAssertFalse(menu().items.contains { $0.title.hasPrefix("Allow Accessibility") })
        hasAccessibility = false
        XCTAssertTrue(menu().items.contains { $0.title.hasPrefix("Allow Accessibility") })
    }

    func testCheckForUpdatesIsAlwaysInTheMenuButTheUpdateItemOnlyWhenOneExists() async throws {
        XCTAssertNotNil(menu().items.first { $0.title == "Check for Updates…" })
        XCTAssertNil(menu().items.first { $0.title.hasPrefix("Update Available") })

        _ = await updates.check()
        let item = try XCTUnwrap(menu().items.first { $0.title.hasPrefix("Update Available") })
        XCTAssertEqual(item.title, "Update Available: SpaceStation 1.5.0…")
        XCTAssertEqual(menu().items.first?.title, item.title, "the update notice leads the menu")
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
