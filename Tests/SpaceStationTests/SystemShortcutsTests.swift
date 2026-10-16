import XCTest
import CoreGraphics

final class KeyBindingTests: XCTestCase {
    func testDisplayShowsModifiersInSystemOrderAndHidesFn() {
        XCTAssertEqual(KeyBinding(keyCode: 1, flags: .maskControl).display, "⌃S")
        let controlOptionS = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue)
        XCTAssertEqual(KeyBinding(keyCode: 1, flags: controlOptionS).display, "⌃⌥S")
        let all = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
                               | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskControl.rawValue)
        XCTAssertEqual(KeyBinding(keyCode: 0, flags: all).display, "⌃⌥⇧⌘A")
        // Arrow keys carry an fn flag that must not be shown.
        XCTAssertEqual(SystemShortcuts.defaultMissionControl.display, "⌃↑")
        XCTAssertEqual(SystemShortcuts.defaultMoveRight.display, "⌃→")
    }

    func testDisplayOfCommonKeys() {
        XCTAssertEqual(KeyBinding(keyCode: 18, flags: .maskControl).display, "⌃1")
        XCTAssertEqual(KeyBinding(keyCode: 49, flags: .maskControl).display, "⌃Space")
        XCTAssertEqual(KeyBinding(keyCode: 122, flags: []).display, "F1")
        XCTAssertEqual(KeyBinding(keyCode: 200, flags: .maskControl).display, "⌃Key 200")
    }

    func testMenuKeyEquivalents() {
        XCTAssertEqual(KeyBinding(keyCode: 18, flags: .maskControl).menuKeyEquivalent, "1")
        XCTAssertEqual(KeyBinding(keyCode: 1, flags: .maskControl).menuKeyEquivalent, "s")
        XCTAssertEqual(KeyBinding(keyCode: 49, flags: .maskControl).menuKeyEquivalent, " ")
        XCTAssertEqual(KeyBinding(keyCode: 126, flags: .maskControl).menuKeyEquivalent?.unicodeScalars.first?.value, 0xF700)
        XCTAssertNil(KeyBinding(keyCode: 200, flags: .maskControl).menuKeyEquivalent)
    }

    func testStorageRoundTrip() {
        let binding = KeyBinding(keyCode: 1, flags: CGEventFlags(rawValue: 786432))
        XCTAssertEqual(KeyBinding(storageValue: binding.storageValue), binding)
        XCTAssertNil(KeyBinding(storageValue: ""))
        XCTAssertNil(KeyBinding(storageValue: "x,y"))
        XCTAssertNil(KeyBinding(storageValue: "1"))
    }
}

final class SystemShortcutsTests: XCTestCase {
    private func domain(_ entries: [Int: (enabled: Int, params: [Int])]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (id, entry) in entries {
            result[String(id)] = ["enabled": entry.enabled, "value": ["parameters": entry.params, "type": "standard"]]
        }
        return ["AppleSymbolicHotKeys": result]
    }

    func testMissingEntryMeansOffForDesktopShortcutsButDefaultForOthers() {
        // The real situation on a Mac where only Desktops 1-6 were ever enabled.
        let hotkeys = domain([118: (1, [65535, 18, 262144])])
        XCTAssertNotNil(SystemShortcuts.switchToDesktop(1, in: hotkeys))
        XCTAssertNil(SystemShortcuts.switchToDesktop(7, in: hotkeys))
        XCTAssertEqual(SystemShortcuts.missionControl(in: hotkeys)?.display, "⌃↑")
        XCTAssertEqual(SystemShortcuts.moveLeftASpace(in: hotkeys)?.display, "⌃←")
        XCTAssertEqual(SystemShortcuts.moveRightASpace(in: hotkeys)?.display, "⌃→")
    }

    func testMissingDomainFallsBackToDefaultsOnlyWhereTheyExist() {
        XCTAssertNil(SystemShortcuts.switchToDesktop(1, in: nil))
        XCTAssertEqual(SystemShortcuts.missionControl(in: nil)?.display, "⌃↑")
    }

    func testDisabledOrUnassignedEntriesAreNilEvenWithADefault() {
        XCTAssertNil(SystemShortcuts.missionControl(in: domain([32: (0, [65535, 126, 8650752])])))
        XCTAssertNil(SystemShortcuts.missionControl(in: domain([32: (1, [65535, 65535, 0])])))
        XCTAssertNil(SystemShortcuts.moveRightASpace(in: domain([81: (1, [1, 2])])))
    }

    func testUserRemappedBindingIsUsed() {
        // Mission Control moved to ⌃⌥M (key 46) by the user.
        let binding = SystemShortcuts.missionControl(in: domain([32: (1, [65535, 46, 786432])]))
        XCTAssertEqual(binding?.display, "⌃⌥M")
    }

    func testDesktopShortcutIndexIsLimitedToOneThroughNine() {
        let hotkeys = domain([127: (1, [65535, 29, 262144])])
        XCTAssertNil(SystemShortcuts.switchToDesktop(0, in: hotkeys))
        XCTAssertNil(SystemShortcuts.switchToDesktop(10, in: hotkeys))
    }
}

final class DockHotCornersTests: XCTestCase {
    func testOnlyCornersWithARealActionAreInUse() {
        // Matches this Mac: top-right and bottom-right set to 1 (no action), top-left/bottom-left absent.
        let dock: [String: Any] = ["wvous-tr-corner": 1, "wvous-br-corner": 1, "wvous-tr-modifier": 0]
        XCTAssertTrue(DockHotCorners.inUse(in: dock).isEmpty)
    }

    func testActionsAreLabelled() {
        let dock: [String: Any] = ["wvous-br-corner": 14, "wvous-tl-corner": 2, "wvous-tr-corner": 13, "wvous-bl-corner": 5]
        let used = DockHotCorners.inUse(in: dock)
        XCTAssertEqual(used[.bottomRight], "Quick Note")
        XCTAssertEqual(used[.topLeft], "Mission Control")
        XCTAssertEqual(used[.topRight], "Lock Screen")
        XCTAssertEqual(used[.bottomLeft], "Start Screen Saver")
    }

    func testCornerThatNeedsAModifierKeyIsNotTaken() {
        let dock: [String: Any] = ["wvous-tr-corner": 2, "wvous-tr-modifier": 131072] // only with Shift
        XCTAssertNil(DockHotCorners.inUse(in: dock)[.topRight])
    }

    func testUnknownActionsAreStillAvoided() {
        XCTAssertEqual(DockHotCorners.inUse(in: ["wvous-tl-corner": 99])[.topLeft], "another macOS action")
    }

    func testNoDomain() {
        XCTAssertTrue(DockHotCorners.inUse(in: nil).isEmpty)
    }
}
