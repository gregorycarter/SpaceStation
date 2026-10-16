import Foundation
import Combine
import CoreGraphics

/// Where the switcher panel appears when opened from a hot corner.
enum PanelPlacement: String, CaseIterable, Identifiable {
    case nearCorner, centered

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nearCorner: return "Next to the corner"
        case .centered: return "Centered on screen"
        }
    }
}

/// The user's settings, persisted in UserDefaults. Views bind to the published properties and
/// the controllers that act on them subscribe to the same publishers.
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    enum Key {
        static let menuBarDisplay = "menuBarDisplay"
        static let shortenMenuBarNames = "shortenMenuBarNames"
        static let switcherShortcut = "switcherShortcut"
        static let hotCorner = "switcherHotCorner"            // same key as before the redesign
        static let hotCornerDelay = "hotCornerDelay"
        static let panelPlacement = "panelPlacement"
        static let showKeyboardHints = "showKeyboardHints"
        static let closeOnPointerExit = "closeOnPointerExit"
        /// Pre-redesign on/off switch for the hardcoded Control+S hotkey.
        static let legacyHotKeyEnabled = "switcherHotKeyEnabled"
    }

    /// Control + Option + S: avoids Control+S's clash with terminals and Emacs-style editors, and
    /// ⌃⌥Space's clash with macOS's input-source shortcut.
    static let defaultShortcut = KeyBinding(
        keyCode: 1, flags: CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue))
    /// What the pre-redesign app hardcoded.
    static let legacyShortcut = KeyBinding(keyCode: 1, flags: .maskControl)

    /// Hot corner delay range, in seconds. The default is "Instant".
    static let delayRange: ClosedRange<Double> = 0.015...1.0
    static let instantDelay = 0.015

    private let defaults: UserDefaults

    @Published var menuBarDisplay: MenuBarDisplay { didSet { defaults.set(menuBarDisplay.rawValue, forKey: Key.menuBarDisplay) } }
    @Published var shortenMenuBarNames: Bool { didSet { defaults.set(shortenMenuBarNames, forKey: Key.shortenMenuBarNames) } }
    /// The global shortcut that opens the switcher, or nil if turned off.
    @Published var switcherShortcut: KeyBinding? { didSet { defaults.set(switcherShortcut?.storageValue ?? "off", forKey: Key.switcherShortcut) } }
    @Published var hotCorner: HotCorner { didSet { defaults.set(hotCorner.rawValue, forKey: Key.hotCorner) } }
    @Published var hotCornerDelay: Double {
        didSet {
            let clamped = min(max(hotCornerDelay, Self.delayRange.lowerBound), Self.delayRange.upperBound)
            if clamped != hotCornerDelay { hotCornerDelay = clamped; return }
            defaults.set(hotCornerDelay, forKey: Key.hotCornerDelay)
        }
    }
    @Published var panelPlacement: PanelPlacement { didSet { defaults.set(panelPlacement.rawValue, forKey: Key.panelPlacement) } }
    @Published var showKeyboardHints: Bool { didSet { defaults.set(showKeyboardHints, forKey: Key.showKeyboardHints) } }
    @Published var closeOnPointerExit: Bool { didSet { defaults.set(closeOnPointerExit, forKey: Key.closeOnPointerExit) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        menuBarDisplay = defaults.string(forKey: Key.menuBarDisplay).flatMap(MenuBarDisplay.init(rawValue:)) ?? .iconAndName
        shortenMenuBarNames = defaults.object(forKey: Key.shortenMenuBarNames) as? Bool ?? true
        switcherShortcut = Self.loadShortcut(from: defaults)
        hotCorner = defaults.string(forKey: Key.hotCorner).flatMap(HotCorner.init(rawValue:)) ?? .off
        let delay = defaults.object(forKey: Key.hotCornerDelay) as? Double ?? Self.instantDelay
        hotCornerDelay = min(max(delay, Self.delayRange.lowerBound), Self.delayRange.upperBound)
        panelPlacement = defaults.string(forKey: Key.panelPlacement).flatMap(PanelPlacement.init(rawValue:)) ?? .centered
        showKeyboardHints = defaults.object(forKey: Key.showKeyboardHints) as? Bool ?? true
        closeOnPointerExit = defaults.object(forKey: Key.closeOnPointerExit) as? Bool ?? false
    }

    /// The saved shortcut, migrating the pre-redesign on/off switch the first time: an install
    /// that had the hardcoded Control+S enabled keeps Control+S rather than silently changing,
    /// one that had turned it off stays off, and a fresh install gets the new default.
    static func loadShortcut(from defaults: UserDefaults) -> KeyBinding? {
        if let stored = defaults.string(forKey: Key.switcherShortcut) {
            return stored == "off" ? nil : KeyBinding(storageValue: stored) ?? defaultShortcut
        }
        let migrated: KeyBinding?
        if let legacyEnabled = defaults.object(forKey: Key.legacyHotKeyEnabled) as? Bool {
            migrated = legacyEnabled ? legacyShortcut : nil
        } else {
            migrated = defaultShortcut
        }
        defaults.set(migrated?.storageValue ?? "off", forKey: Key.switcherShortcut)
        defaults.removeObject(forKey: Key.legacyHotKeyEnabled)
        return migrated
    }
}
