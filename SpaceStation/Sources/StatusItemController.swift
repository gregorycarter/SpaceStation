import AppKit
import Combine
import os.log

/// The menu bar item and its native menu.
///
/// A real NSMenu (rather than a custom panel) gives keyboard navigation, type-select and
/// VoiceOver for free. Each Space is an item with its icon, a checkmark on the current one and,
/// when macOS has a shortcut for it, that shortcut shown; holding Option swaps every Space row
/// for its Rename action.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    /// Nil when built without installing (unit tests build menus without touching the menu bar).
    private var statusItem: NSStatusItem?
    private let spaceTracker: SpaceTracker
    private let nameManager: SpaceNameManager
    private let preferences: AppPreferences
    private let actions: Actions
    private var subscriptions = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "StatusItem")

    /// What the menu can ask the app to do.
    struct Actions {
        var rename: (SpaceInfo) -> Void
        var showSwitcher: () -> Void
        var showSettings: () -> Void
        var showAbout: () -> Void
        var allowAccessibility: () -> Void
        var handleSwitchOutcome: (SpaceTracker.SwitchOutcome) -> Void
    }

    init(spaceTracker: SpaceTracker, nameManager: SpaceNameManager, preferences: AppPreferences,
         actions: Actions, installStatusItem: Bool = true) {
        self.spaceTracker = spaceTracker
        self.nameManager = nameManager
        self.preferences = preferences
        self.actions = actions
        super.init()

        guard installStatusItem else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.setAccessibilityLabel("SpaceStation")

        // Refresh the button whenever anything it shows may have changed. The publishers fire
        // before the value changes, so read it on the next run loop turn.
        let refresh: () -> Void = { [weak self] in DispatchQueue.main.async { self?.updateButton() } }
        spaceTracker.objectWillChange.sink { refresh() }.store(in: &subscriptions)
        nameManager.objectWillChange.sink { refresh() }.store(in: &subscriptions)
        preferences.objectWillChange.sink { refresh() }.store(in: &subscriptions)
        updateButton()
    }

    // MARK: - Status item button

    /// The anchor view for popovers.
    var button: NSStatusBarButton? { statusItem?.button }

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        let display = preferences.menuBarDisplay

        let image: NSImage?
        let name: String
        if spaceTracker.isInFullscreenSpace {
            image = SpaceIconImage.symbol(SpaceIconImage.fullscreenSymbol)
            name = "Full Screen"
        } else {
            let space = spaceTracker.currentSpace
            image = SpaceIconImage.image(for: nameManager.icon(for: space), index: space.index)
            name = nameManager.name(for: space)
        }

        button.image = display.showsIcon ? image : nil
        button.title = display.showsName ? MenuBarFormat.displayName(name, shorten: preferences.shortenMenuBarNames) : ""
        button.imagePosition = display.showsName && display.showsIcon ? .imageLeading : (display.showsIcon ? .imageOnly : .noImage)
        button.toolTip = name
        button.setAccessibilityLabel("SpaceStation, \(name)")
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        spaceTracker.checkAccessibilityPermission()
        populate(menu)
    }

    /// Fills `menu` from the current state.
    func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !spaceTracker.hasAccessibilityPermission {
            let item = NSMenuItem(title: "Allow Accessibility to Switch Spaces…", action: #selector(allowAccessibility), keyEquivalent: "")
            item.target = self
            item.image = SpaceIconImage.symbol("exclamationmark.triangle.fill")
            menu.addItem(item)
            menu.addItem(.separator())
        }

        // macOS 13 has no section-header item, so a disabled item stands in.
        let header = NSMenuItem(title: "Spaces", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let hotkeys = SystemShortcuts.current()
        for space in spaceTracker.spaces {
            addSpaceItems(for: space, hotkeys: hotkeys, to: menu)
        }

        menu.addItem(.separator())

        let current = spaceTracker.currentSpace
        let renameTitle = spaceTracker.isInFullscreenSpace ? "Rename Space…" : "Rename “\(nameManager.name(for: current))”…"
        let rename = NSMenuItem(title: renameTitle, action: #selector(renameCurrent), keyEquivalent: "")
        rename.target = self
        rename.isEnabled = !spaceTracker.isInFullscreenSpace && current.id != SpaceInfo.placeholder.id
        menu.addItem(rename)

        let switcher = NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: "")
        switcher.target = self
        if let binding = preferences.switcherShortcut { Self.apply(binding, to: switcher) }
        menu.addItem(switcher)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let about = NSMenuItem(title: "About SpaceStation", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit SpaceStation", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    /// One Space row, followed by its hidden Option alternate (Rename).
    private func addSpaceItems(for space: SpaceInfo, hotkeys: [String: Any]?, to menu: NSMenu) {
        let name = nameManager.name(for: space)
        let icon = SpaceIconImage.image(for: nameManager.icon(for: space), index: space.index)
        let isCurrent = !spaceTracker.isInFullscreenSpace && space.index == spaceTracker.currentSpaceIndex
        let binding = SystemShortcuts.switchToDesktop(space.index, in: hotkeys)

        let switchItem = NSMenuItem(title: name, action: #selector(chooseSpace(_:)), keyEquivalent: "")
        switchItem.target = self
        switchItem.representedObject = space
        switchItem.image = icon
        switchItem.state = isCurrent ? .on : .off
        if let binding { Self.apply(binding, to: switchItem) }
        menu.addItem(switchItem)

        let renameItem = NSMenuItem(title: "Rename “\(name)”…", action: #selector(renameSpace(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = space
        renameItem.image = icon
        renameItem.isAlternate = true
        // An alternate must share the primary's key equivalent and add its own modifier.
        if let binding {
            Self.apply(binding, to: renameItem)
            renameItem.keyEquivalentModifierMask.insert(.option)
        } else {
            renameItem.keyEquivalentModifierMask = [.option]
        }
        menu.addItem(renameItem)
    }

    /// Shows a shortcut on a menu item. Status item menus only act on key equivalents while open,
    /// so this is mainly a reminder of the real, system-wide shortcut.
    private static func apply(_ binding: KeyBinding, to item: NSMenuItem) {
        guard let key = binding.menuKeyEquivalent else { return }
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = modifierMask(for: binding.flags)
    }

    static func modifierMask(for flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if flags.contains(.maskControl) { mask.insert(.control) }
        if flags.contains(.maskAlternate) { mask.insert(.option) }
        if flags.contains(.maskShift) { mask.insert(.shift) }
        if flags.contains(.maskCommand) { mask.insert(.command) }
        return mask
    }

    // MARK: - Actions

    @objc private func chooseSpace(_ item: NSMenuItem) {
        guard let space = item.representedObject as? SpaceInfo else { return }
        actions.handleSwitchOutcome(spaceTracker.switchTo(space))
    }

    @objc private func renameSpace(_ item: NSMenuItem) {
        guard let space = item.representedObject as? SpaceInfo else { return }
        actions.rename(space)
    }

    @objc private func renameCurrent() { actions.rename(spaceTracker.currentSpace) }
    @objc private func showSwitcher() { actions.showSwitcher() }
    @objc private func showSettings() { actions.showSettings() }
    @objc private func showAbout() { actions.showAbout() }
    @objc private func allowAccessibility() { actions.allowAccessibility() }
}
