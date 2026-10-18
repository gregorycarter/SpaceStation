import Foundation
import Cocoa
import Combine
import os.log

/// Tracks the current Space (virtual desktop) and notifies observers of changes
@MainActor
class SpaceTracker: ObservableObject {
    @Published private(set) var currentSpaceIndex: Int = 1
    @Published private(set) var spaces: [SpaceInfo] = [.placeholder]
    /// True while the active Space is a fullscreen app rather than a desktop.
    @Published private(set) var isInFullscreenSpace: Bool = false
    /// Every Space on the focused display (fullscreen included), for stepping with the arrow shortcuts.
    @Published private(set) var spaceOrder: SpaceOrder?
    /// The desktop that was current before the present one, so the switcher can open on it and
    /// open + Return toggles between the last two Spaces.
    @Published private(set) var previousSpaceID: String?
    private var history = SpaceHistory()
    @Published private(set) var isTrackingAvailable: Bool = true
    @Published private(set) var hasAccessibilityPermission: Bool = false
    /// Set when Accessibility isn't granted and the build's signature suggests why.
    @Published private(set) var accessibilityHint: CodeSigning.AccessibilityHint?
    /// True when "Switch to Desktop N" is enabled for every desktop that exists (up to 9).
    @Published private(set) var hasKeyboardShortcutsEnabled: Bool = false
    /// Desktops (1-based, up to 9) whose "Switch to Desktop N" shortcut is not enabled.
    @Published private(set) var missingShortcuts: [Int] = []
    /// Desktops (1-based) whose "Switch to Desktop N" shortcut is enabled in the preferences but
    /// that macOS did not act on when it was sent, which means the Dock's copy of the shortcuts is
    /// stale. Switching to these steps with the arrow shortcuts instead until the Dock is restarted.
    @Published private(set) var staleShortcutDesktops: Set<Int> = []

    /// The current desktop Space (never empty; falls back to a placeholder).
    var currentSpace: SpaceInfo {
        spaces.first { $0.index == currentSpaceIndex } ?? spaces.first ?? .placeholder
    }

    private var spaceChangeObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "SpaceTracker")
    private let accessibility: AccessibilityController
    private let switchExecutor: SpaceSwitchExecutor
    private var subscriptions = Set<AnyCancellable>()

    init() {
        accessibility = AccessibilityController()
        switchExecutor = SpaceSwitchExecutor()
        accessibility.$isTrusted
            .sink { [weak self] in self?.hasAccessibilityPermission = $0 }
            .store(in: &subscriptions)
        accessibility.$hint
            .sink { [weak self] in self?.accessibilityHint = $0 }
            .store(in: &subscriptions)
        checkAccessibilityPermission()
        checkKeyboardShortcuts()
        setupSpaceChangeObserver()
        updateCurrentSpace()
        accessibility.startMonitoring()
    }

    deinit {
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
    }

    // Keep the existing observable interface for views and controllers.
    func checkAccessibilityPermission() { accessibility.check() }
    func requestAccessibilityPermission() { accessibility.request() }
    func openAccessibilitySettings() { accessibility.openSettings() }
    func resetAndRequestPermission(openSettings: Bool = true) {
        accessibility.resetAndRequest(openSettings: openSettings)
    }

    // MARK: - Keyboard Shortcuts Check

    func checkKeyboardShortcuts() {
        // "Switch to Desktop N" shortcuts live in com.apple.symbolichotkeys,
        // keys 118-126 (Desktop 1-9). macOS only offers (and enables) them for
        // desktops that exist, so a Mac with 7 desktops can have 6 of 7 enabled.
        let hotkeys = SystemShortcuts.current()
        let missing = SystemShortcuts.missingDesktopShortcuts(spaceCount: spaces.count, in: hotkeys)
        missingShortcuts = missing
        hasKeyboardShortcutsEnabled = missing.isEmpty
        logger.info("Keyboard shortcuts: \(missing.isEmpty ? "all enabled" : "missing for desktops \(missing)")")
    }

    // MARK: - Space Change Observer

    private func setupSpaceChangeObserver() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentSpace()
            }
        }
        logger.debug("Space change observer registered")
    }

    private func updateCurrentSpace() {
        let snapshot = readSpaces()
        let isFullscreen = snapshot.currentIndex == nil
        // In a fullscreen Space there is no desktop index; keep the last known one.
        let newIndex = snapshot.currentIndex ?? currentSpaceIndex

        if snapshot.spaces != spaces || newIndex != currentSpaceIndex || isFullscreen != isInFullscreenSpace {
            logger.info("Space changed: index=\(newIndex), total=\(snapshot.spaces.count), fullscreen=\(isFullscreen)")
        }

        let spacesChanged = snapshot.spaces != spaces
        spaces = snapshot.spaces
        currentSpaceIndex = newIndex
        isInFullscreenSpace = isFullscreen
        recordPreviousSpace()
        // The set of shortcuts that matter depends on how many desktops exist.
        if spacesChanged { checkKeyboardShortcuts() }
    }

    private func recordPreviousSpace() {
        guard !switchExecutor.isStepping else { return }
        let current = isInFullscreenSpace ? nil : spaces.first(where: { $0.index == currentSpaceIndex })?.id
        history.record(currentDesktopID: current == SpaceInfo.placeholder.id ? nil : current)
        if previousSpaceID != history.previousID { previousSpaceID = history.previousID }
    }

    /// `currentIndex` is nil when the active Space is not a desktop (e.g. a fullscreen app).
    private func readSpaces() -> SpaceSnapshot.Desktops {
        let fallback = SpaceSnapshot.Desktops.placeholder
        let conn = CGSMainConnectionID()

        guard conn != 0 else {
            logger.warning("Failed to get CGS connection ID")
            isTrackingAvailable = false
            return fallback
        }

        guard let spacesRef = CGSCopyManagedDisplaySpaces(conn),
              let displays = spacesRef as? [[String: Any]] else {
            logger.warning("Failed to get managed display spaces")
            isTrackingAvailable = false
            return fallback
        }

        isTrackingAvailable = true
        let snapshot = SpaceSnapshot.parse(displays: displays, focusedDisplayUUID: Self.focusedDisplayUUID())
        spaceOrder = snapshot?.order

        guard let desktops = snapshot?.desktops else {
            logger.debug("No spaces found, returning defaults")
            return fallback
        }
        return desktops
    }

    /// UUID string of the display with keyboard focus, if it can be determined.
    private static func focusedDisplayUUID() -> String? {
        guard let screen = NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    // MARK: - Space Switching

    enum SwitchOutcome: Equatable {
        /// A shortcut was sent (or stepping toward the Space has begun).
        case started
        case alreadyCurrent
        case needsAccessibility
        /// macOS has neither a "Switch to Desktop N" shortcut for this Space nor usable
        /// "Move left/right a space" shortcuts to step to it.
        case unavailable
    }

    /// Switch to a desktop. Uses the user's "Switch to Desktop N" shortcut when macOS has one
    /// enabled (Desktops 1-9), and otherwise steps there with the "Move left/right a space"
    /// shortcuts, which works for any number of Spaces. Never posts a key that isn't one of
    /// macOS's own enabled shortcuts, since it would otherwise land in the frontmost app.
    @discardableResult
    func switchTo(_ space: SpaceInfo) -> SwitchOutcome {
        guard space.id != SpaceInfo.placeholder.id else { return .unavailable }
        if !isInFullscreenSpace && space.index == currentSpaceIndex { return .alreadyCurrent }

        // Re-check permission before attempting
        checkAccessibilityPermission()
        guard hasAccessibilityPermission else {
            logger.warning("Cannot switch space - no accessibility permission")
            requestAccessibilityPermission()
            return .needsAccessibility
        }

        let hotkeys = SystemShortcuts.current()
        var useDirectShortcut = !staleShortcutDesktops.contains(space.index)
        #if DEBUG
        // Test hook (Debug builds only): force the arrow-key stepping path.
        if ProcessInfo.processInfo.environment["SPACESTATION_DEBUG_FORCE_STEP"] != nil { useDirectShortcut = false }
        #endif
        if useDirectShortcut, let direct = SystemShortcuts.switchToDesktop(space.index, in: hotkeys) {
            logger.info("Switching to space \(space.index) with its shortcut")
            confirmDirectSwitch(direct, to: space)
            return .started
        }
        return step(to: space, hotkeys: hotkeys)
    }

    /// Sends the direct shortcut and checks that it worked. If macOS ignored it, remember that
    /// and reach the Space by stepping, so the switch still happens.
    private func confirmDirectSwitch(_ binding: KeyBinding, to space: SpaceInfo) {
        Task { @MainActor [self] in
            let arrived = await switchExecutor.postAndConfirm(
                binding,
                isDestination: { !isInFullscreenSpace && currentSpaceIndex == space.index },
                refresh: { updateCurrentSpace() })
            guard !arrived else {
                if staleShortcutDesktops.remove(space.index) != nil { logger.info("Shortcut for space \(space.index) works again") }
                return
            }
            logger.warning("Shortcut for space \(space.index) was ignored; the Dock's shortcuts look stale")
            staleShortcutDesktops.insert(space.index)
            _ = step(to: space, hotkeys: SystemShortcuts.current())
        }
    }

    /// Steps to `space` with the "Move left/right a space" shortcuts.
    private func step(to space: SpaceInfo, hotkeys: [String: Any]?) -> SwitchOutcome {
        guard let order = spaceOrder, let plan = SpaceStepper.plan(order: order, to: space.id) else {
            logger.warning("Space \(space.index) has no shortcut and can't be stepped to")
            checkKeyboardShortcuts()
            return .unavailable
        }
        // Both directions are needed: the first plan may need a correction the other way.
        guard let left = SystemShortcuts.moveLeftASpace(in: hotkeys),
              let right = SystemShortcuts.moveRightASpace(in: hotkeys) else {
            logger.warning("Space \(space.index) has no shortcut and the Move a space shortcuts are off")
            return .unavailable
        }
        guard !switchExecutor.isStepping else { return .started }

        logger.info("Stepping \(plan.steps) to space \(space.index)")
        switchExecutor.start(to: space.id, firstPlan: plan, moveLeft: left, moveRight: right,
                             currentOrder: { [self] in spaceOrder }, refresh: { [self] in updateCurrentSpace() })
        return .started
    }

    // MARK: - Repairing stale shortcuts

    /// Restarts the Dock, which reloads the "Switch to Desktop N" shortcuts. It relaunches by
    /// itself within a second and needs no permission.
    func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        do {
            try process.run()
            logger.info("Restarted the Dock to reload the Switch to Desktop shortcuts")
            staleShortcutDesktops = []   // Try the direct shortcuts again.
        } catch {
            logger.error("Could not restart the Dock: \(error.localizedDescription)")
        }
    }
}

// MARK: - Private Core Graphics APIs

// CGSConnectionID is a C `int` (32-bit), so it must be Int32, not Int.
typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: CGSConnectionID) -> CFArray?
