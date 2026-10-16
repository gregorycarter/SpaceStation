import Foundation
import CoreGraphics

/// What the General tab says about macOS's shortcuts, computed from the `com.apple.symbolichotkeys`
/// preferences and the number of Spaces. Pure so it can be tested.
struct ShortcutSummary: Equatable {
    /// Desktops (1-9) that exist and have no enabled "Switch to Desktop N" shortcut.
    let missingDesktops: [Int]
    /// Desktops (1-9) that exist and do have one.
    let enabledDesktops: [Int]
    /// Spaces beyond 9, which can only ever be reached by stepping.
    let hasSpacesBeyondNine: Bool
    let missionControl: KeyBinding?
    let moveLeft: KeyBinding?
    let moveRight: KeyBinding?
    let firstEnabled: KeyBinding?
    let lastEnabled: KeyBinding?

    /// Stepping between Spaces needs both "Move left a space" and "Move right a space".
    var canStep: Bool { moveLeft != nil && moveRight != nil }

    /// Some Space has no direct shortcut and stepping is turned off, so it can't be switched to.
    var hasUnreachableSpaces: Bool { !canStep && (!missingDesktops.isEmpty || hasSpacesBeyondNine) }

    static func make(spaceCount: Int, hotkeys: [String: Any]?) -> ShortcutSummary {
        let reachable = max(0, min(spaceCount, 9))
        var enabled: [Int] = []
        var missing: [Int] = []
        var bindings: [Int: KeyBinding] = [:]
        for n in 1...max(reachable, 1) where n <= reachable {
            if let binding = SystemShortcuts.switchToDesktop(n, in: hotkeys) {
                enabled.append(n)
                bindings[n] = binding
            } else {
                missing.append(n)
            }
        }
        return ShortcutSummary(
            missingDesktops: missing,
            enabledDesktops: enabled,
            hasSpacesBeyondNine: spaceCount > 9,
            missionControl: SystemShortcuts.missionControl(in: hotkeys),
            moveLeft: SystemShortcuts.moveLeftASpace(in: hotkeys),
            moveRight: SystemShortcuts.moveRightASpace(in: hotkeys),
            firstEnabled: enabled.first.flatMap { bindings[$0] },
            lastEnabled: enabled.last.flatMap { bindings[$0] }
        )
    }

    /// e.g. "Switch to Space 1–7"
    var switchRowLabel: String {
        guard let first = enabledDesktops.first, let last = enabledDesktops.last else { return "Switch to Space 1–9" }
        return first == last ? "Switch to Space \(first)" : "Switch to Space \(first)–\(last)"
    }

    /// e.g. "⌃1 – ⌃7"
    var switchRowValue: String {
        guard let first = firstEnabled, let last = lastEnabled else { return "None enabled" }
        return enabledDesktops.count == 1 ? first.display : "\(first.display) – \(last.display)"
    }
}

enum SpaceListFormat {
    /// "Space 8", "Spaces 8 and 9", "Spaces 5–9" (three or more in a row), "Spaces 3, 5 and 7".
    static func describe(_ numbers: [Int]) -> String {
        let sorted = Array(Set(numbers)).sorted()
        guard !sorted.isEmpty else { return "No Spaces" }
        if sorted.count == 1 { return "Space \(sorted[0])" }

        // Collapse runs of three or more into a range.
        var parts: [String] = []
        var index = 0
        while index < sorted.count {
            var end = index
            while end + 1 < sorted.count, sorted[end + 1] == sorted[end] + 1 { end += 1 }
            if end - index >= 2 {
                parts.append("\(sorted[index])–\(sorted[end])")
            } else {
                parts.append(contentsOf: sorted[index...end].map(String.init))
            }
            index = end + 1
        }
        if parts.count == 1 { return "Spaces \(parts[0])" }
        return "Spaces " + parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }
}

extension SystemShortcuts {
    /// Names for macOS shortcuts that commonly clash with a global hotkey.
    private static let knownNames: [Int: String] = [
        32: "Mission Control", 34: "Application windows", 36: "Show Desktop",
        60: "Select the previous input source", 61: "Select next source in Input menu",
        64: "Spotlight search", 65: "Finder search window",
        79: "Move left a space", 81: "Move right a space",
        52: "Turn Dock hiding on/off", 98: "Show Help menu",
    ]

    private static let comparedModifiers: UInt64 = CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskShift.rawValue | CGEventFlags.maskCommand.rawValue

    /// The name of an enabled macOS shortcut that uses the same keys as `binding`, if any.
    static func conflict(for binding: KeyBinding, in hotkeys: [String: Any]?) -> String? {
        guard let entries = hotkeys?["AppleSymbolicHotKeys"] as? [String: Any] else { return nil }
        for (key, value) in entries {
            guard let id = Int(key), let other = SystemShortcuts.binding(id: id, in: hotkeys),
                  other.keyCode == binding.keyCode,
                  other.flags.rawValue & comparedModifiers == binding.flags.rawValue & comparedModifiers else { continue }
            _ = value
            if (118...126).contains(id) { return "Switch to Desktop \(id - 117)" }
            return knownNames[id] ?? "another macOS shortcut"
        }
        return nil
    }
}

enum ShortcutValidation {
    /// A global shortcut must include Control, Option or Command (Shift alone would swallow
    /// ordinary typing), unless it is a function key.
    static func isAcceptable(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        if KeyCodeNames.isFunctionKey(keyCode) { return true }
        guard KeyCodeNames.display(for: keyCode) != nil else { return false }
        return flags.contains(.maskControl) || flags.contains(.maskAlternate) || flags.contains(.maskCommand)
    }
}

extension KeyCodeNames {
    static func isFunctionKey(_ keyCode: CGKeyCode) -> Bool {
        [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111].contains(keyCode)
    }
}
