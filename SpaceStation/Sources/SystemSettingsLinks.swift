import AppKit

/// Panes of System Settings that SpaceStation points people to. The identifiers have changed
/// between macOS versions, so each pane tries several and finally falls back to System Settings
/// itself.
enum SystemSettingsPane {
    case keyboardShortcuts, desktopAndDock, accessibility

    var urls: [String] {
        switch self {
        case .keyboardShortcuts:
            return ["x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
                    "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"]
        case .desktopAndDock:
            return ["x-apple.systempreferences:com.apple.Desktop-Settings.extension",
                    "x-apple.systempreferences:com.apple.preference.dock"]
        case .accessibility:
            return ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
        }
    }

    func open() {
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
        if let url = URL(string: "x-apple.systempreferences:") { NSWorkspace.shared.open(url) }
    }
}
