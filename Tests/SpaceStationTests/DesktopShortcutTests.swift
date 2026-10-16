import XCTest
import CoreGraphics

final class DesktopShortcutTests: XCTestCase {
    private func hotkeys(key: Int, enabled: Int = 1, parameters: [Int]) -> [String: Any] {
        ["AppleSymbolicHotKeys": [
            String(key): ["enabled": enabled, "value": ["parameters": parameters, "type": "standard"]]
        ]]
    }

    func testEnabledShortcutIsParsed() {
        // Key 118 = Switch to Desktop 1; parameters = [ascii, keyCode, modifiers]; 262144 = Control.
        let domain = hotkeys(key: 118, parameters: [65535, 18, 262144])
        let shortcut = SystemShortcuts.switchToDesktop(1, in: domain)
        XCTAssertEqual(shortcut?.keyCode, 18)
        XCTAssertEqual(shortcut?.flags, .maskControl)
    }

    func testDesktopNMapsToKey117PlusN() {
        let domain = hotkeys(key: 120, parameters: [65535, 20, 262144])
        XCTAssertEqual(SystemShortcuts.switchToDesktop(3, in: domain)?.keyCode, 20)
        XCTAssertNil(SystemShortcuts.switchToDesktop(2, in: domain))
    }

    func testDisabledShortcutIsNil() {
        XCTAssertNil(SystemShortcuts.switchToDesktop(1, in: hotkeys(key: 118, enabled: 0, parameters: [65535, 18, 262144])))
    }

    func testUnassignedKeyIsNil() {
        XCTAssertNil(SystemShortcuts.switchToDesktop(1, in: hotkeys(key: 118, parameters: [65535, 65535, 0])))
    }

    func testMalformedOrMissingDataIsNil() {
        XCTAssertNil(SystemShortcuts.switchToDesktop(1, in: nil))
        XCTAssertNil(SystemShortcuts.switchToDesktop(1, in: [:]))
        XCTAssertNil(SystemShortcuts.switchToDesktop(1, in: hotkeys(key: 118, parameters: [1, 2])))
    }

    func testIndexOutsideOneToNineIsNil() {
        let domain = hotkeys(key: 127, parameters: [65535, 18, 262144])
        XCTAssertNil(SystemShortcuts.switchToDesktop(0, in: domain))
        XCTAssertNil(SystemShortcuts.switchToDesktop(10, in: domain))
    }
}

final class MissingShortcutTests: XCTestCase {
    /// Hotkeys with "Switch to Desktop N" enabled for the given desktops.
    private func hotkeys(enabled desktops: [Int]) -> [String: Any] {
        var entries: [String: Any] = [:]
        for n in desktops {
            entries[String(117 + n)] = ["enabled": 1, "value": ["parameters": [65535, 17 + n, 262144], "type": "standard"]]
        }
        return ["AppleSymbolicHotKeys": entries]
    }

    func testSevenDesktopsWithSixShortcutsReportsDesktopSeven() {
        // The real-world case: Desktops 1-6 enabled, 7 exists but its shortcut was never turned on.
        XCTAssertEqual(SystemShortcuts.missingDesktopShortcuts(spaceCount: 7, in: hotkeys(enabled: [1, 2, 3, 4, 5, 6])), [7])
    }

    func testOnlyDesktopsThatExistAreRequired() {
        XCTAssertEqual(SystemShortcuts.missingDesktopShortcuts(spaceCount: 3, in: hotkeys(enabled: [1, 2, 3])), [])
        XCTAssertEqual(SystemShortcuts.missingDesktopShortcuts(spaceCount: 3, in: hotkeys(enabled: [1, 2])), [3])
    }

    func testRequirementIsCappedAtNine() {
        XCTAssertEqual(SystemShortcuts.missingDesktopShortcuts(spaceCount: 12, in: hotkeys(enabled: Array(1...6))), [7, 8, 9])
        XCTAssertEqual(SystemShortcuts.missingDesktopShortcuts(spaceCount: 12, in: hotkeys(enabled: Array(1...9))), [])
    }

    func testMissingDomainMeansAllMissing() {
        XCTAssertEqual(SystemShortcuts.missingDesktopShortcuts(spaceCount: 2, in: nil), [1, 2])
    }
}
