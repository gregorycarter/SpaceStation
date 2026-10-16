import AppKit
import Combine

/// Shared state for the Settings tabs: the app's models plus what macOS currently says about
/// shortcuts and hot corners, re-read whenever Settings opens or the app is activated.
@MainActor
final class SettingsModel: ObservableObject {
    let spaceTracker: SpaceTracker
    let nameManager: SpaceNameManager
    let preferences: AppPreferences

    @Published private(set) var summary: ShortcutSummary
    /// Hot corners macOS already uses, with what they do.
    @Published private(set) var usedCorners: [HotCorner: String] = [:]
    /// What the chosen switcher shortcut clashes with in macOS, if anything.
    @Published private(set) var shortcutConflict: String?

    private var subscriptions = Set<AnyCancellable>()

    init(spaceTracker: SpaceTracker, nameManager: SpaceNameManager, preferences: AppPreferences) {
        self.spaceTracker = spaceTracker
        self.nameManager = nameManager
        self.preferences = preferences
        summary = ShortcutSummary.make(spaceCount: spaceTracker.spaces.count, hotkeys: SystemShortcuts.current())
        refresh()

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        spaceTracker.$spaces.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &subscriptions)
        preferences.$switcherShortcut.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &subscriptions)
    }

    func refresh() {
        let hotkeys = SystemShortcuts.current()
        summary = ShortcutSummary.make(spaceCount: spaceTracker.spaces.count, hotkeys: hotkeys)
        usedCorners = DockHotCorners.current()
        shortcutConflict = preferences.switcherShortcut.flatMap { SystemShortcuts.conflict(for: $0, in: hotkeys) }
        spaceTracker.checkAccessibilityPermission()
        spaceTracker.checkKeyboardShortcuts()
    }
}
