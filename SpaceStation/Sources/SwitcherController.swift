import SwiftUI
import Carbon.HIToolbox
import os.log

/// Window that can take keyboard focus without activating the whole app, and that
/// lets the controller handle keys before SwiftUI sees them.
private final class SwitcherPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyDown?(event) == true { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// Observable state for the switcher strip.
@MainActor
final class SwitcherModel: ObservableObject {
    @Published var spaces: [SpaceInfo] = []
    @Published var names: [String] = []
    @Published var icons: [SpaceIcon] = []
    @Published var currentIndex: Int?
    @Published var selectedIndex = 0
}

/// Shows a floating strip of the user's named Spaces and switches to the one picked.
/// This replaces nothing in Mission Control (macOS offers no way to rename its labels);
/// it is SpaceStation's own switcher.
@MainActor
final class SwitcherController {
    static let shared = SwitcherController()

    /// Whether the global hotkey is registered. Stored under this key by Settings.
    static let hotKeyEnabledKey = "switcherHotKeyEnabled"
    /// Control + S. Note this shadows ⌃S in every other app (terminals, Emacs-style editors)
    /// while the hotkey is enabled; users can turn it off in Settings.
    private static let hotKeyCode = kVK_ANSI_S
    private static let hotKeyModifiers = controlKey

    private let model = SwitcherModel()
    private let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "Switcher")
    private var panel: SwitcherPanel?
    private var hotKey: GlobalHotKey?
    private var spaceTracker: SpaceTracker?
    private var nameManager: SpaceNameManager?
    private var isDismissing = false

    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    func configure(spaceTracker: SpaceTracker, nameManager: SpaceNameManager) {
        self.spaceTracker = spaceTracker
        self.nameManager = nameManager
        UserDefaults.standard.register(defaults: [Self.hotKeyEnabledKey: true])
        applyHotKeyPreference()
    }

    /// Registers or unregisters the hotkey to match the stored preference.
    func applyHotKeyPreference() {
        if UserDefaults.standard.bool(forKey: Self.hotKeyEnabledKey) {
            guard hotKey == nil else { return }
            hotKey = GlobalHotKey(keyCode: Self.hotKeyCode, modifiers: Self.hotKeyModifiers) { [weak self] in
                Task { @MainActor in self?.toggle() }
            }
            if hotKey == nil {
                logger.warning("Could not register the switcher hotkey (already in use?)")
            }
        } else {
            hotKey = nil
        }
    }

    func toggle() {
        isVisible ? dismiss() : show()
    }

    func show() {
        guard let spaceTracker, let nameManager else { return }
        guard !isVisible else { return }

        refreshModel(spaceTracker: spaceTracker, nameManager: nameManager)

        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Size to the cards, but never wider than the screen.
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let cardWidth: CGFloat = 140 + 12
        let desired = CGFloat(model.spaces.count) * cardWidth + 32
        let width = min(max(desired, 260), visible.width - 48)
        let height: CGFloat = 130
        panel.setFrame(NSRect(x: visible.midX - width / 2,
                              y: visible.maxY - height - 16,
                              width: width, height: height), display: true)

        isDismissing = false
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        guard let panel, panel.isVisible, !isDismissing else { return }
        isDismissing = true
        panel.orderOut(nil)
        // Hand focus back to whichever app was frontmost, so the Space-switch
        // keystroke isn't delivered to us.
        NSApp.hide(nil)
    }

    // MARK: - Private

    private func refreshModel(spaceTracker: SpaceTracker, nameManager: SpaceNameManager) {
        model.spaces = spaceTracker.spaces
        model.names = spaceTracker.spaces.map { nameManager.name(for: $0) }
        model.icons = spaceTracker.spaces.map { nameManager.icon(for: $0) }
        model.currentIndex = spaceTracker.isInFullscreenSpace ? nil : spaceTracker.currentSpaceIndex
        model.selectedIndex = max(0, (model.currentIndex ?? 1) - 1)
    }

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 130),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Appear over the current Space, including fullscreen apps.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false

        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onResignKey = { [weak self] in
            Task { @MainActor in self?.dismiss() }
        }

        let root = SwitcherRoot(model: model) { [weak self] space in self?.pick(space) }
        panel.contentView = NSHostingView(rootView: root)
        return panel
    }

    /// Returns true if the key was handled.
    private func handleKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Escape:
            dismiss()
            return true
        case kVK_LeftArrow:
            moveSelection(by: -1)
            return true
        case kVK_RightArrow:
            moveSelection(by: 1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
            if model.spaces.indices.contains(model.selectedIndex) {
                pick(model.spaces[model.selectedIndex])
            }
            return true
        default:
            if let digit = event.charactersIgnoringModifiers.flatMap(Int.init), digit >= 1,
               let space = model.spaces.first(where: { $0.index == digit }) {
                pick(space)
                return true
            }
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !model.spaces.isEmpty else { return }
        model.selectedIndex = (model.selectedIndex + delta + model.spaces.count) % model.spaces.count
    }

    private func pick(_ space: SpaceInfo) {
        guard let spaceTracker else { return }
        dismiss()
        // Give the previously active app a moment to regain focus first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            SetupWindowController.shared.switchOrShowSetup(spaceTracker: spaceTracker, to: space.index)
        }
    }
}

private struct SwitcherRoot: View {
    @ObservedObject var model: SwitcherModel
    let onPick: (SpaceInfo) -> Void

    var body: some View {
        SwitcherView(spaces: model.spaces,
                     names: model.names,
                     icons: model.icons,
                     currentIndex: model.currentIndex,
                     selectedIndex: model.selectedIndex,
                     onPick: onPick)
            .padding(6)
    }
}
