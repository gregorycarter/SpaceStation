import SwiftUI
import Combine
import Carbon.HIToolbox
import os.log

/// Window that can take keyboard focus without activating the whole app, and that lets the
/// controller handle keys before SwiftUI sees them. Its configuration (a non-activating,
/// floating, all-Spaces panel) is what lets it appear over fullscreen apps and take the hotkey
/// and hot corner; change it only with care.
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

/// The panel's rounded, blurred background. It also reports where the pointer is, so hover can
/// move the selection and "close when the pointer leaves" works, without depending on SwiftUI
/// hover support inside a non-activating panel.
private final class SwitcherBackgroundView: NSVisualEffectView {
    var onPointerMoved: ((CGPoint) -> Void)?   // top-left origin
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?

    private let solidBackground = NSView()
    private let innerHighlight = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        // A non-activating panel never becomes the active window; with the default state it
        // would always show the flat inactive look.
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5

        solidBackground.wantsLayer = true
        solidBackground.autoresizingMask = [.width, .height]
        solidBackground.isHidden = true
        addSubview(solidBackground)

        innerHighlight.cornerRadius = 15.5
        innerHighlight.borderWidth = 0.5
        layer?.addSublayer(innerHighlight)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Reduce Transparency uses a solid background; Increase Contrast a stronger border.
    func configureAccessibility(reduceTransparency: Bool, increaseContrast: Bool) {
        solidBackground.isHidden = !reduceTransparency
        layer?.borderWidth = increaseContrast ? 1 : 0.5
        updateAppearanceColors()
    }

    override func layout() {
        super.layout()
        solidBackground.frame = bounds
        innerHighlight.frame = bounds.insetBy(dx: 0.5, dy: 0.5)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceColors()
    }

    private func updateAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
            solidBackground.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            innerHighlight.borderColor = dark ? NSColor.white.withAlphaComponent(0.13).cgColor : NSColor.clear.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onPointerMoved?(CGPoint(x: point.x, y: bounds.height - point.y))
    }

    override func mouseEntered(with event: NSEvent) { onPointerEntered?() }
    override func mouseExited(with event: NSEvent) { onPointerExited?() }
}

/// Shows a floating panel of the user's Spaces and switches to the one picked.
@MainActor
final class SwitcherController {
    static let shared = SwitcherController()

    /// What opened the panel; it decides where the panel appears.
    enum Trigger: Equatable {
        case hotkey
        case menu
        case hotCorner(HotCorner)
    }

    private let model = SwitcherModel()
    private let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "Switcher")
    private var panel: SwitcherPanel?
    private var background: SwitcherBackgroundView?
    private var hotKey: GlobalHotKey?
    private var hotCornerMonitor: HotCornerMonitor?
    private var spaceTracker: SpaceTracker?
    private var nameManager: SpaceNameManager?
    private var preferences: AppPreferences?
    private var handleOutcome: ((SpaceTracker.SwitchOutcome) -> Void)?
    private var subscriptions = Set<AnyCancellable>()

    private var typeSelect = TypeSelectBuffer()
    private var isDismissing = false
    private var pointerHasEntered = false
    private var pendingPointerClose: DispatchWorkItem?

    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    func configure(spaceTracker: SpaceTracker, nameManager: SpaceNameManager, preferences: AppPreferences,
                   handleOutcome: @escaping (SpaceTracker.SwitchOutcome) -> Void) {
        guard self.spaceTracker == nil else { return }
        self.spaceTracker = spaceTracker
        self.nameManager = nameManager
        self.preferences = preferences
        self.handleOutcome = handleOutcome
        logger.info("Switcher configured")

        // Build the panel now so the first appearance isn't slowed by creating it.
        if panel == nil { panel = makePanel() }

        preferences.$switcherShortcut
            .sink { [weak self] binding in self?.registerHotKey(binding) }
            .store(in: &subscriptions)
        Publishers.CombineLatest(preferences.$hotCorner, preferences.$hotCornerDelay)
            .sink { [weak self] corner, delay in self?.startHotCorner(corner, delay: delay) }
            .store(in: &subscriptions)
    }

    // MARK: - Triggers

    private func registerHotKey(_ binding: KeyBinding?) {
        hotKey = nil
        guard let binding else {
            logger.info("Switcher hotkey off")
            return
        }
        hotKey = GlobalHotKey(keyCode: Int(binding.keyCode), modifiers: binding.carbonModifiers) { [weak self] in
            Task { @MainActor in self?.toggle(trigger: .hotkey) }
        }
        if hotKey == nil {
            logger.warning("Could not register the switcher hotkey (already in use?)")
        } else {
            logger.info("Switcher hotkey registered: \(binding.display, privacy: .public)")
        }
    }

    private func startHotCorner(_ corner: HotCorner, delay: TimeInterval) {
        hotCornerMonitor = nil
        guard corner != .off else {
            logger.info("Hot corner off")
            return
        }
        logger.info("Hot corner active: \(corner.rawValue, privacy: .public)")
        hotCornerMonitor = HotCornerMonitor(corner: corner, dwell: delay) { [weak self] in
            guard let self, !self.isVisible else { return }
            self.logger.info("Hot corner triggered")
            self.show(trigger: .hotCorner(corner))
        }
    }

    func toggle(trigger: Trigger) {
        isVisible ? dismiss() : show(trigger: trigger)
    }

    // MARK: - Showing and hiding

    func show(trigger: Trigger) {
        guard let spaceTracker, let nameManager, let preferences else { return }
        guard !isVisible else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel

        refreshModel(spaceTracker: spaceTracker, nameManager: nameManager, preferences: preferences)

        let screen = Self.screenUnderPointer()
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        model.cardWidth = SwitcherLayout.cardWidth(count: model.items.count, availableWidth: visible.width)
        let size = CGSize(width: SwitcherLayout.panelWidth(count: model.items.count, cardWidth: model.cardWidth),
                          height: SwitcherLayout.panelHeight(count: model.items.count, showsFooter: model.showsHints))

        var anchor = SwitcherAnchor.centered
        if case .hotCorner(let corner) = trigger, preferences.panelPlacement == .nearCorner { anchor = .corner(corner) }
        let frame = SwitcherPlacement.frame(size: size, visibleFrame: visible, anchor: anchor)

        let workspace = NSWorkspace.shared
        background?.configureAccessibility(reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                                           increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast)
        typeSelect.reset()
        pointerHasEntered = false
        pendingPointerClose?.cancel()
        isDismissing = false

        // Appear with a short fade, and (unless Reduce Motion is on) a slight scale up from 0.98.
        let reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
        let startFrame = reduceMotion ? frame : frame.insetBy(dx: frame.width * 0.01, dy: frame.height * 0.01)
        panel.alphaValue = 0
        panel.setFrame(startFrame, display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
    }

    func dismiss() {
        guard let panel, panel.isVisible, !isDismissing else { return }
        isDismissing = true
        pendingPointerClose?.cancel()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1
                // Hand focus back to whichever app was frontmost.
                NSApp.hide(nil)
                self?.isDismissing = false
            }
        })
    }

    private static func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    // MARK: - Model

    private func refreshModel(spaceTracker: SpaceTracker, nameManager: SpaceNameManager, preferences: AppPreferences) {
        model.items = spaceTracker.spaces.map { SwitcherItem(space: $0, name: nameManager.name(for: $0), icon: nameManager.icon(for: $0)) }
        model.currentID = spaceTracker.isInFullscreenSpace ? nil : spaceTracker.currentSpace.id
        model.selectedIndex = SwitcherLayout.initialSelection(ids: model.items.map(\.id),
                                                              currentID: model.currentID,
                                                              previousID: spaceTracker.previousSpaceID)
        model.showsHints = preferences.showKeyboardHints
        model.highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    // MARK: - Panel

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 160),
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
        panel.acceptsMouseMovedEvents = true

        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onResignKey = { [weak self] in
            Task { @MainActor in self?.dismiss() }
        }

        let background = SwitcherBackgroundView(frame: panel.contentRect(forFrameRect: panel.frame))
        background.autoresizingMask = [.width, .height]
        background.onPointerMoved = { [weak self] point in self?.pointerMoved(to: point) }
        background.onPointerEntered = { [weak self] in
            self?.pointerHasEntered = true
            self?.pendingPointerClose?.cancel()
        }
        background.onPointerExited = { [weak self] in self?.pointerExited() }

        let host = NSHostingView(rootView: SwitcherView(model: model) { [weak self] space in self?.pick(space) })
        host.frame = background.bounds
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)

        panel.contentView = background
        self.background = background
        return panel
    }

    // MARK: - Pointer

    private func pointerMoved(to point: CGPoint) {
        guard let index = SwitcherLayout.cardIndex(at: point, count: model.items.count, cardWidth: model.cardWidth),
              index != model.selectedIndex else { return }
        model.selectedIndex = index
    }

    /// With "Close when the pointer leaves" on, close shortly after the pointer exits, but only
    /// if it had entered first (the panel can open with the pointer elsewhere).
    private func pointerExited() {
        guard preferences?.closeOnPointerExit == true, pointerHasEntered else { return }
        pendingPointerClose?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        pendingPointerClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - Keyboard

    /// Returns true if the key was handled.
    private func handleKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Escape:
            dismiss()
            return true
        case kVK_LeftArrow: return move(.left)
        case kVK_RightArrow: return move(.right)
        case kVK_UpArrow: return move(.up)
        case kVK_DownArrow: return move(.down)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if model.items.indices.contains(model.selectedIndex) {
                pick(model.items[model.selectedIndex].space)
            }
            return true
        default:
            return handleCharacter(event)
        }
    }

    private func move(_ direction: SwitcherLayout.Direction) -> Bool {
        model.selectedIndex = SwitcherLayout.move(from: model.selectedIndex, direction: direction, count: model.items.count)
        typeSelect.reset()
        return true
    }

    /// 1-9 jump straight to that Space; other characters build a type-to-select prefix.
    private func handleCharacter(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            return false
        }
        if let digit = Int(characters), (1...9).contains(digit) {
            if model.items.indices.contains(digit - 1) { pick(model.items[digit - 1].space) }
            return true
        }
        guard characters.rangeOfCharacter(from: .controlCharacters) == nil else { return false }
        let prefix = typeSelect.append(characters, at: ProcessInfo.processInfo.systemUptime)
        if let match = TypeSelectBuffer.firstMatch(prefix: prefix, in: model.items.map(\.name)) {
            model.selectedIndex = match
        }
        return true
    }

    // MARK: - Picking

    private func pick(_ space: SpaceInfo) {
        guard let spaceTracker else { return }
        dismiss()
        // The shortcut is a system-wide key press, so send it as the panel fades.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            let outcome = spaceTracker.switchTo(space)
            self?.handleOutcome?(outcome)
        }
    }
}
