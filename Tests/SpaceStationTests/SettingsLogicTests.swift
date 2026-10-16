import XCTest
import CoreGraphics

final class ShortcutSummaryTests: XCTestCase {
    private func domain(enabled desktops: [Int], extra: [Int: (Int, [Int])] = [:]) -> [String: Any] {
        var entries: [String: Any] = [:]
        for n in desktops {
            entries[String(117 + n)] = ["enabled": 1, "value": ["parameters": [65535, 17 + n, 262144], "type": "standard"]]
        }
        for (id, e) in extra {
            entries[String(id)] = ["enabled": e.0, "value": ["parameters": e.1, "type": "standard"]]
        }
        return ["AppleSymbolicHotKeys": entries]
    }

    func testThisMacsSituationSevenSpacesWithSixShortcuts() {
        let summary = ShortcutSummary.make(spaceCount: 7, hotkeys: domain(enabled: [1, 2, 3, 4, 5, 6]))
        XCTAssertEqual(summary.missingDesktops, [7])
        XCTAssertEqual(summary.enabledDesktops, [1, 2, 3, 4, 5, 6])
        XCTAssertFalse(summary.hasSpacesBeyondNine)
        XCTAssertTrue(summary.canStep)                       // move left/right default to on
        XCTAssertFalse(summary.hasUnreachableSpaces)
        XCTAssertEqual(summary.missionControl?.display, "⌃↑")
        XCTAssertEqual(summary.switchRowLabel, "Switch to Space 1–6")
    }

    func testOnlySpacesThatExistAreCounted() {
        let summary = ShortcutSummary.make(spaceCount: 3, hotkeys: domain(enabled: [1, 2, 3]))
        XCTAssertTrue(summary.missingDesktops.isEmpty)
        XCTAssertEqual(summary.switchRowValue, "⌃1 – ⌃3")
    }

    func testSpacesBeyondNineNeedStepping() {
        let summary = ShortcutSummary.make(spaceCount: 12, hotkeys: domain(enabled: Array(1...9)))
        XCTAssertTrue(summary.hasSpacesBeyondNine)
        XCTAssertTrue(summary.missingDesktops.isEmpty)
    }

    func testSteppingDisabledMakesMissingSpacesUnreachable() {
        let hotkeys = domain(enabled: [1, 2], extra: [79: (0, [65535, 123, 8650752]), 81: (1, [65535, 124, 8650752])])
        let summary = ShortcutSummary.make(spaceCount: 4, hotkeys: hotkeys)
        XCTAssertFalse(summary.canStep)   // move-left is off
        XCTAssertTrue(summary.hasUnreachableSpaces)
        XCTAssertEqual(summary.missingDesktops, [3, 4])
    }

    func testNothingEnabled() {
        let summary = ShortcutSummary.make(spaceCount: 2, hotkeys: nil)
        XCTAssertEqual(summary.missingDesktops, [1, 2])
        XCTAssertEqual(summary.switchRowValue, "None enabled")
    }

    func testSingleEnabledShortcutRow() {
        let summary = ShortcutSummary.make(spaceCount: 5, hotkeys: domain(enabled: [1]))
        XCTAssertEqual(summary.switchRowLabel, "Switch to Space 1")
        XCTAssertEqual(summary.switchRowValue, "⌃1")
    }
}

final class SpaceListFormatTests: XCTestCase {
    func testDescriptions() {
        XCTAssertEqual(SpaceListFormat.describe([8]), "Space 8")
        XCTAssertEqual(SpaceListFormat.describe([8, 9]), "Spaces 8 and 9")
        XCTAssertEqual(SpaceListFormat.describe([5, 6, 7, 8, 9]), "Spaces 5–9")
        XCTAssertEqual(SpaceListFormat.describe([3, 5, 7]), "Spaces 3, 5 and 7")
        XCTAssertEqual(SpaceListFormat.describe([1, 2, 3, 5, 6]), "Spaces 1–3, 5 and 6")
        XCTAssertEqual(SpaceListFormat.describe([9, 8, 8]), "Spaces 8 and 9")
        XCTAssertEqual(SpaceListFormat.describe([]), "No Spaces")
    }
}

final class ShortcutConflictTests: XCTestCase {
    private func hotkeys(_ id: Int, enabled: Int = 1, key: Int, modifiers: Int) -> [String: Any] {
        ["AppleSymbolicHotKeys": [String(id): ["enabled": enabled, "value": ["parameters": [65535, key, modifiers], "type": "standard"]]]]
    }

    func testControlOptionSpaceClashesWithTheInputSourceShortcut() {
        let domain = hotkeys(61, key: 49, modifiers: 786432)
        let binding = KeyBinding(keyCode: 49, flags: CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue))
        XCTAssertEqual(SystemShortcuts.conflict(for: binding, in: domain), "Select next source in Input menu")
    }

    func testDisabledSystemShortcutsDoNotConflict() {
        // This Mac: the input-source shortcuts exist but are off.
        let domain = hotkeys(61, enabled: 0, key: 49, modifiers: 786432)
        let binding = KeyBinding(keyCode: 49, flags: CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue))
        XCTAssertNil(SystemShortcuts.conflict(for: binding, in: domain))
    }

    func testDefaultSwitcherShortcutIsFreeOfOrdinarySystemShortcuts() {
        let domain = hotkeys(64, key: 49, modifiers: 1048576)   // Spotlight, ⌘Space
        XCTAssertNil(SystemShortcuts.conflict(for: AppPreferences.defaultShortcut, in: domain))
    }

    func testDesktopSwitchShortcutIsNamedByDesktop() {
        let domain = hotkeys(120, key: 20, modifiers: 262144)
        XCTAssertEqual(SystemShortcuts.conflict(for: KeyBinding(keyCode: 20, flags: .maskControl), in: domain), "Switch to Desktop 3")
    }

    func testDifferentModifiersDoNotConflict() {
        let domain = hotkeys(60, key: 49, modifiers: 262144)    // ⌃Space
        XCTAssertNil(SystemShortcuts.conflict(for: KeyBinding(keyCode: 49, flags: .maskCommand), in: domain))
    }

    func testNoDomain() {
        XCTAssertNil(SystemShortcuts.conflict(for: KeyBinding(keyCode: 1, flags: .maskControl), in: nil))
    }
}

final class ShortcutValidationTests: XCTestCase {
    func testNeedsAControlOptionOrCommandModifier() {
        XCTAssertTrue(ShortcutValidation.isAcceptable(keyCode: 1, flags: .maskControl))
        XCTAssertTrue(ShortcutValidation.isAcceptable(keyCode: 1, flags: .maskAlternate))
        XCTAssertTrue(ShortcutValidation.isAcceptable(keyCode: 1, flags: .maskCommand))
        XCTAssertFalse(ShortcutValidation.isAcceptable(keyCode: 1, flags: []))
        XCTAssertFalse(ShortcutValidation.isAcceptable(keyCode: 1, flags: .maskShift), "Shift alone would swallow typing")
    }

    func testFunctionKeysAreAllowedBare() {
        XCTAssertTrue(ShortcutValidation.isAcceptable(keyCode: 122, flags: []))
    }

    func testUnknownKeysAreRejected() {
        XCTAssertFalse(ShortcutValidation.isAcceptable(keyCode: 200, flags: .maskControl))
    }
}
