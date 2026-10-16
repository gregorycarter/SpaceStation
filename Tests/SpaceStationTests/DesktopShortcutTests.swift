import XCTest
import CoreGraphics
@testable import SpaceStation

final class DesktopShortcutTests: XCTestCase {
    private func hotkeys(key: Int, enabled: Int = 1, parameters: [Int]) -> [String: Any] {
        ["AppleSymbolicHotKeys": [
            String(key): ["enabled": enabled, "value": ["parameters": parameters, "type": "standard"]]
        ]]
    }

    func testEnabledShortcutIsParsed() {
        // Key 118 = Switch to Desktop 1; parameters = [ascii, keyCode, modifiers]; 262144 = Control.
        let domain = hotkeys(key: 118, parameters: [65535, 18, 262144])
        let shortcut = SpaceTracker.desktopShortcut(for: 1, in: domain)
        XCTAssertEqual(shortcut?.keyCode, 18)
        XCTAssertEqual(shortcut?.flags, .maskControl)
    }

    func testDesktopNMapsToKey117PlusN() {
        let domain = hotkeys(key: 120, parameters: [65535, 20, 262144])
        XCTAssertEqual(SpaceTracker.desktopShortcut(for: 3, in: domain)?.keyCode, 20)
        XCTAssertNil(SpaceTracker.desktopShortcut(for: 2, in: domain))
    }

    func testDisabledShortcutIsNil() {
        XCTAssertNil(SpaceTracker.desktopShortcut(for: 1, in: hotkeys(key: 118, enabled: 0, parameters: [65535, 18, 262144])))
    }

    func testUnassignedKeyIsNil() {
        XCTAssertNil(SpaceTracker.desktopShortcut(for: 1, in: hotkeys(key: 118, parameters: [65535, 65535, 0])))
    }

    func testMalformedOrMissingDataIsNil() {
        XCTAssertNil(SpaceTracker.desktopShortcut(for: 1, in: nil))
        XCTAssertNil(SpaceTracker.desktopShortcut(for: 1, in: [:]))
        XCTAssertNil(SpaceTracker.desktopShortcut(for: 1, in: hotkeys(key: 118, parameters: [1, 2])))
    }

    func testIndexOutsideOneToNineIsNil() {
        let domain = hotkeys(key: 127, parameters: [65535, 18, 262144])
        XCTAssertNil(SpaceTracker.desktopShortcut(for: 0, in: domain))
        XCTAssertNil(SpaceTracker.desktopShortcut(for: 10, in: domain))
    }
}
