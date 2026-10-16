import Foundation
import CoreGraphics

/// A keyboard shortcut: a virtual key code plus modifier flags.
struct KeyBinding: Equatable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags

    /// Modifier bits that are shown to the user. The fn bit that macOS adds to arrow keys is
    /// kept in `flags` (it must be sent when posting the shortcut) but never displayed.
    private static let displayedModifiers: [(CGEventFlags, String)] = [
        (.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘"),
    ]

    /// e.g. "⌃⌥S", "⌃1", "⌃↑".
    var display: String {
        let modifiers = Self.displayedModifiers.filter { flags.contains($0.0) }.map(\.1).joined()
        return modifiers + (KeyCodeNames.display(for: keyCode) ?? "Key \(keyCode)")
    }

    /// The `NSMenuItem.keyEquivalent` string for this key, if it can be expressed.
    var menuKeyEquivalent: String? { KeyCodeNames.menuKeyEquivalent(for: keyCode) }

    /// Compact text form for UserDefaults: "<keyCode>,<flags>".
    var storageValue: String { "\(keyCode),\(flags.rawValue)" }

    init(keyCode: CGKeyCode, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.flags = flags
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: ",")
        guard parts.count == 2, let key = UInt16(parts[0]), let raw = UInt64(parts[1]) else { return nil }
        self.init(keyCode: key, flags: CGEventFlags(rawValue: raw))
    }
}

/// A "Switch to Desktop N" shortcut (kept as an alias; it is just a key binding).
typealias DesktopShortcut = KeyBinding

/// Names for ANSI virtual key codes.
enum KeyCodeNames {
    private static let letters: [CGKeyCode: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
        12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p",
        37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
    ]
    private static let digits: [CGKeyCode: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
    ]
    private static let punctuation: [CGKeyCode: String] = [
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
    ]
    private static let arrows: [CGKeyCode: (glyph: String, scalar: UInt32)] = [
        123: ("←", 0xF702), 124: ("→", 0xF703), 125: ("↓", 0xF701), 126: ("↑", 0xF700),
    ]
    private static let special: [CGKeyCode: String] = [
        49: "Space", 36: "Return", 48: "Tab", 53: "Esc", 51: "Delete",
    ]
    private static let functionKeys: [CGKeyCode: Int] = [
        122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10, 103: 11, 111: 12,
    ]

    /// How the key is shown in text, e.g. "S", "1", "↑", "Space".
    static func display(for keyCode: CGKeyCode) -> String? {
        if let letter = letters[keyCode] { return letter.uppercased() }
        if let digit = digits[keyCode] { return digit }
        if let mark = punctuation[keyCode] { return mark }
        if let arrow = arrows[keyCode] { return arrow.glyph }
        if let name = special[keyCode] { return name }
        if let number = functionKeys[keyCode] { return "F\(number)" }
        return nil
    }

    /// The character an `NSMenuItem` uses as its key equivalent, if there is one.
    static func menuKeyEquivalent(for keyCode: CGKeyCode) -> String? {
        if let letter = letters[keyCode] { return letter }
        if let digit = digits[keyCode] { return digit }
        if let mark = punctuation[keyCode] { return mark }
        if let arrow = arrows[keyCode], let scalar = UnicodeScalar(arrow.scalar) { return String(Character(scalar)) }
        if keyCode == 49 { return " " }
        return nil
    }
}

/// Reads macOS's own shortcuts from the `com.apple.symbolichotkeys` preference domain.
///
/// A missing entry means different things per shortcut: the "Switch to Desktop N" shortcuts are
/// off unless present, while Mission Control and "Move left/right a space" use their default
/// binding when absent. `defaultBinding` captures that.
enum SystemShortcuts {
    enum ID {
        static let missionControl = 32
        static let moveLeftASpace = 79
        static let moveRightASpace = 81
        static func switchToDesktop(_ n: Int) -> Int { 117 + n }
    }

    // Arrow-key defaults carry the fn modifier macOS adds to them.
    private static let controlFn = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskSecondaryFn.rawValue)
    static let defaultMissionControl = KeyBinding(keyCode: 126, flags: controlFn)
    static let defaultMoveLeft = KeyBinding(keyCode: 123, flags: controlFn)
    static let defaultMoveRight = KeyBinding(keyCode: 124, flags: controlFn)

    /// The binding for `id`: the user's if the entry exists and is enabled, nil if it exists
    /// but is disabled or unusable, and `defaultBinding` if there is no entry at all.
    static func binding(id: Int, in hotkeys: [String: Any]?, defaultBinding: KeyBinding? = nil) -> KeyBinding? {
        guard let entries = hotkeys?["AppleSymbolicHotKeys"] as? [String: Any],
              let entry = entries[String(id)] as? [String: Any] else {
            return defaultBinding
        }
        guard (entry["enabled"] as? Int) == 1,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int],
              parameters.count >= 3,
              (0..<65535).contains(parameters[1]),   // 65535 means "no key assigned"
              parameters[2] >= 0 else {
            return nil
        }
        // The stored modifier mask uses the same bit layout as CGEventFlags.
        return KeyBinding(keyCode: CGKeyCode(parameters[1]), flags: CGEventFlags(rawValue: UInt64(parameters[2])))
    }

    static func switchToDesktop(_ n: Int, in hotkeys: [String: Any]?) -> KeyBinding? {
        guard (1...9).contains(n) else { return nil }
        return binding(id: ID.switchToDesktop(n), in: hotkeys)
    }

    static func missionControl(in hotkeys: [String: Any]?) -> KeyBinding? {
        binding(id: ID.missionControl, in: hotkeys, defaultBinding: defaultMissionControl)
    }

    static func moveLeftASpace(in hotkeys: [String: Any]?) -> KeyBinding? {
        binding(id: ID.moveLeftASpace, in: hotkeys, defaultBinding: defaultMoveLeft)
    }

    static func moveRightASpace(in hotkeys: [String: Any]?) -> KeyBinding? {
        binding(id: ID.moveRightASpace, in: hotkeys, defaultBinding: defaultMoveRight)
    }

    /// The live preference domain.
    static func current() -> [String: Any]? {
        UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys")
    }
}

/// What a macOS Hot Corner (System Settings > Desktop & Dock) is set to do.
enum DockCornerAction: Int {
    case missionControl = 2, applicationWindows = 3, desktop = 4, startScreenSaver = 5
    case disableScreenSaver = 6, dashboard = 7, displaySleep = 10, launchpad = 11
    case notificationCenter = 12, lockScreen = 13, quickNote = 14

    var label: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .applicationWindows: return "Application Windows"
        case .desktop: return "Desktop"
        case .startScreenSaver: return "Start Screen Saver"
        case .disableScreenSaver: return "Disable Screen Saver"
        case .dashboard: return "Dashboard"
        case .displaySleep: return "Put Display to Sleep"
        case .launchpad: return "Launchpad"
        case .notificationCenter: return "Notification Center"
        case .lockScreen: return "Lock Screen"
        case .quickNote: return "Quick Note"
        }
    }
}

/// Reads the macOS Hot Corner settings from the `com.apple.dock` preference domain.
enum DockHotCorners {
    /// Corners macOS already uses. A value of 0 or 1 means "no action", and a corner that only
    /// fires while a modifier key is held (`wvous-*-modifier`) is not treated as taken. An
    /// unrecognised action number is reported with a generic label so the corner is still avoided.
    static func inUse(in dock: [String: Any]?) -> [HotCorner: String] {
        let keys: [(HotCorner, String)] = [
            (.topLeft, "tl"), (.topRight, "tr"), (.bottomLeft, "bl"), (.bottomRight, "br"),
        ]
        var result: [HotCorner: String] = [:]
        for (corner, suffix) in keys {
            guard let action = dock?["wvous-\(suffix)-corner"] as? Int, action > 1 else { continue }
            let modifier = dock?["wvous-\(suffix)-modifier"] as? Int ?? 0
            guard modifier == 0 else { continue }
            result[corner] = DockCornerAction(rawValue: action)?.label ?? "another macOS action"
        }
        return result
    }

    static func current() -> [HotCorner: String] {
        inUse(in: UserDefaults.standard.persistentDomain(forName: "com.apple.dock"))
    }
}
