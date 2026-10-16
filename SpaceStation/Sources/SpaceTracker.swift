import Foundation
import Cocoa
import Combine
import os.log
import ApplicationServices

/// A desktop Space. `id` is stable across reordering, so names are keyed on it;
/// `index` is the 1-based position in Mission Control and can change.
struct SpaceInfo: Identifiable, Equatable {
    let id: String
    let index: Int

    /// Used when Space detection fails, so the UI always has something to show.
    static let placeholder = SpaceInfo(id: "placeholder", index: 1)
}

/// A "Switch to Desktop N" keyboard shortcut.
struct DesktopShortcut: Equatable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

/// Tracks the current Space (virtual desktop) and notifies observers of changes
@MainActor
class SpaceTracker: ObservableObject {
    @Published private(set) var currentSpaceIndex: Int = 1
    @Published private(set) var spaces: [SpaceInfo] = [.placeholder]
    /// True while the active Space is a fullscreen app rather than a desktop.
    @Published private(set) var isInFullscreenSpace: Bool = false
    @Published private(set) var isTrackingAvailable: Bool = true
    @Published private(set) var hasAccessibilityPermission: Bool = false
    /// Set when Accessibility isn't granted and the build's signature suggests why.
    @Published private(set) var accessibilityHint: CodeSigning.AccessibilityHint?
    /// True when "Switch to Desktop N" is enabled for every desktop that exists (up to 9).
    @Published private(set) var hasKeyboardShortcutsEnabled: Bool = false
    /// Desktops (1-based, up to 9) whose "Switch to Desktop N" shortcut is not enabled.
    @Published private(set) var missingShortcuts: [Int] = []

    /// macOS only provides "Switch to Desktop N" shortcuts for Desktops 1-9.
    nonisolated static let maxSwitchableSpace = 9

    var totalSpaces: Int { spaces.count }

    /// The current desktop Space (never empty; falls back to a placeholder).
    var currentSpace: SpaceInfo {
        spaces.first { $0.index == currentSpaceIndex } ?? spaces.first ?? .placeholder
    }

    // Registered once for the app's lifetime (SpaceTracker is owned by the App), so it is never removed.
    private var spaceChangeObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "SpaceTracker")
    private let signingIdentity = CodeSigning.current()
    private static let lastTrustedRequirementKey = "lastAccessibilityTrustedRequirement"
    private static let lastAutoResetRequirementKey = "lastAccessibilityAutoResetRequirement"
    private var accessibilityObserver: NSObjectProtocol?

    init() {
        logger.info("SpaceTracker initializing")
        checkAccessibilityPermission()
        checkKeyboardShortcuts()
        setupSpaceChangeObserver()
        updateCurrentSpace()
        observeAccessibilityChanges()
        healStaleAccessibilityGrantIfNeeded()
    }

    /// macOS posts this when any app's Accessibility permission changes, so we notice a
    /// toggle in System Settings immediately instead of waiting for the next poll.
    private func observeAccessibilityChanges() {
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The trust database updates just after the notification arrives.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Task { @MainActor in self?.checkAccessibilityPermission() }
            }
        }
    }

    /// If the app's signing requirement differs from the one that was granted access, the old
    /// grant can't apply but still looks enabled in System Settings. Clear our entry once and
    /// re-prompt so the user only has to switch it on, instead of diagnosing a stale toggle.
    private func healStaleAccessibilityGrantIfNeeded() {
        // The unit-test host launches the real app; never touch the user's permissions from tests.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        let defaults = UserDefaults.standard
        guard CodeSigning.shouldAutoResetStaleGrant(
                hint: accessibilityHint,
                identity: signingIdentity,
                lastAutoResetRequirement: defaults.string(forKey: Self.lastAutoResetRequirementKey)),
              let requirement = signingIdentity?.requirement else { return }

        defaults.set(requirement, forKey: Self.lastAutoResetRequirementKey)
        logger.info("Stale Accessibility grant for a previous signature; resetting it once")
        resetAndRequestPermission(openSettings: false)
    }

    // MARK: - Accessibility Permission

    func checkAccessibilityPermission() {
        // Use AXIsProcessTrustedWithOptions for a fresh check (not cached)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        updateAccessibilityState(trusted: trusted)
        logger.info("Accessibility permission check: \(trusted)")
    }

    /// Records the result, and remembers which signing requirement was last trusted so a
    /// later "not trusted" under a different signature can be explained and healed.
    private func updateAccessibilityState(trusted: Bool) {
        hasAccessibilityPermission = trusted
        if trusted, let requirement = signingIdentity?.requirement {
            UserDefaults.standard.set(requirement, forKey: Self.lastTrustedRequirementKey)
        }
        accessibilityHint = CodeSigning.accessibilityHint(
            isTrusted: trusted,
            identity: signingIdentity,
            lastTrustedRequirement: UserDefaults.standard.string(forKey: Self.lastTrustedRequirementKey))
    }

    func requestAccessibilityPermission() {
        logger.info("Requesting accessibility permission")

        // This will prompt the user to grant accessibility permission
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        updateAccessibilityState(trusted: trusted)
        logger.info("Accessibility permission after request: \(trusted)")
    }

    func openAccessibilitySettings() {
        logger.info("Opening Accessibility settings")

        // First trigger the system prompt which adds us to the list
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Also open settings so user can toggle if needed
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func resetAndRequestPermission(openSettings: Bool = true) {
        logger.info("Resetting and requesting accessibility permission")

        let bundleID = Bundle.main.bundleIdentifier ?? "com.gregorycarter.SpaceStation"
        let logger = self.logger

        // Reset the TCC entry for this app (it must then be re-added). Run it off
        // the main thread so the UI doesn't freeze while tccutil executes.
        Task.detached { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            task.arguments = ["reset", "Accessibility", bundleID]
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                logger.error("tccutil failed: \(error.localizedDescription)")
            }

            // Small delay to let TCC process the reset
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self?.requestPermissionAndOpenSettings(openSettings: openSettings)
        }
    }

    private func requestPermissionAndOpenSettings(openSettings: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        updateAccessibilityState(trusted: trusted)
        logger.info("Permission after reset: \(trusted)")

        if openSettings, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Keyboard Shortcuts Check

    func checkKeyboardShortcuts() {
        // "Switch to Desktop N" shortcuts live in com.apple.symbolichotkeys,
        // keys 118-126 (Desktop 1-9). macOS only offers (and enables) them for
        // desktops that exist, so a Mac with 7 desktops can have 6 of 7 enabled.
        let hotkeys = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys")
        let missing = Self.missingShortcuts(spaceCount: spaces.count, in: hotkeys)
        missingShortcuts = missing
        hasKeyboardShortcutsEnabled = missing.isEmpty
        logger.info("Keyboard shortcuts: \(missing.isEmpty ? "all enabled" : "missing for desktops \(missing)")")
    }

    /// Which of the first `spaceCount` desktops (capped at 9) have no enabled switch shortcut.
    nonisolated static func missingShortcuts(spaceCount: Int, in hotkeys: [String: Any]?) -> [Int] {
        guard spaceCount >= 1 else { return [] }
        return (1...min(spaceCount, maxSwitchableSpace)).filter { desktopShortcut(for: $0, in: hotkeys) == nil }
    }

    /// The key and modifiers the user has configured for "Switch to Desktop N",
    /// or nil if that shortcut is disabled or can't be read.
    private func desktopShortcut(for index: Int) -> DesktopShortcut? {
        let hotkeys = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys")
        return Self.desktopShortcut(for: index, in: hotkeys)
    }

    /// Pure parser for the `com.apple.symbolichotkeys` domain (testable).
    nonisolated static func desktopShortcut(for index: Int, in hotkeys: [String: Any]?) -> DesktopShortcut? {
        guard (1...maxSwitchableSpace).contains(index),
              let symbolicHotkeys = hotkeys?["AppleSymbolicHotKeys"] as? [String: Any],
              let entry = symbolicHotkeys[String(117 + index)] as? [String: Any],
              (entry["enabled"] as? Int) == 1,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int],
              parameters.count >= 3,
              // 65535 means "no key assigned"
              (0..<65535).contains(parameters[1]),
              parameters[2] >= 0 else {
            return nil
        }
        // The stored modifier mask uses the same bit layout as CGEventFlags.
        return DesktopShortcut(keyCode: CGKeyCode(parameters[1]),
                               flags: CGEventFlags(rawValue: UInt64(parameters[2])))
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
        // The set of shortcuts that matter depends on how many desktops exist.
        if spacesChanged { checkKeyboardShortcuts() }
    }

    /// `currentIndex` is nil when the active Space is not a desktop (e.g. a fullscreen app).
    private func readSpaces() -> (spaces: [SpaceInfo], currentIndex: Int?) {
        let fallback: (spaces: [SpaceInfo], currentIndex: Int?) = ([.placeholder], 1)
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

        guard let snapshot = Self.parseSpaces(displays: displays, focusedDisplayUUID: Self.focusedDisplayUUID()) else {
            logger.debug("No spaces found, returning defaults")
            return fallback
        }
        return snapshot
    }

    /// Pure parser for the `CGSCopyManagedDisplaySpaces` result (testable).
    /// Returns nil if no usable display/desktop is found.
    nonisolated static func parseSpaces(displays: [[String: Any]],
                                        focusedDisplayUUID: String?) -> (spaces: [SpaceInfo], currentIndex: Int?)? {
        guard let display = activeDisplay(in: displays, focusedDisplayUUID: focusedDisplayUUID),
              let currentSpace = display["Current Space"] as? [String: Any],
              let currentID = currentSpace["ManagedSpaceID"] as? Int,
              let allSpaces = display["Spaces"] as? [[String: Any]] else {
            return nil
        }

        // Only desktop Spaces (type 0); fullscreen apps (type 4) are excluded.
        let desktops = allSpaces.filter { ($0["type"] as? Int ?? 0) == 0 }
        guard !desktops.isEmpty else { return nil }

        let infos = desktops.enumerated().map { offset, space in
            SpaceInfo(id: stableID(for: space), index: offset + 1)
        }
        let currentIndex = desktops.firstIndex { ($0["ManagedSpaceID"] as? Int) == currentID }
            .map { $0 + 1 }
        return (infos, currentIndex)
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

    /// With "Displays have separate Spaces" each display has its own Spaces. Use the
    /// one the user is working on (the screen with keyboard focus), not just the first.
    nonisolated private static func activeDisplay(in displays: [[String: Any]],
                                                  focusedDisplayUUID: String?) -> [String: Any]? {
        guard displays.count > 1 else { return displays.first }

        if let focusedDisplayUUID,
           let match = displays.first(where: {
               ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(focusedDisplayUUID) == .orderedSame
           }) {
            return match
        }

        return displays.first { ($0["Display Identifier"] as? String) == "Main" } ?? displays.first
    }

    /// Prefer the Space's uuid; some Spaces report an empty one, so fall back to
    /// the managed Space ID.
    nonisolated static func stableID(for space: [String: Any]) -> String {
        if let uuid = space["uuid"] as? String, !uuid.isEmpty {
            return uuid
        }
        let managedID = space["ManagedSpaceID"] as? Int ?? 0
        return "managed-\(managedID)"
    }

    // MARK: - Space Switching

    /// Switch to a specific space by index
    /// Returns true if the switch was attempted, false if permissions are missing
    @discardableResult
    func switchToSpace(_ index: Int) -> Bool {
        guard (1...Self.maxSwitchableSpace).contains(index) else {
            logger.warning("Invalid space index: \(index)")
            return false
        }

        // Re-check permission before attempting
        checkAccessibilityPermission()

        guard hasAccessibilityPermission else {
            logger.warning("Cannot switch space - no accessibility permission")
            requestAccessibilityPermission()
            return false
        }

        // Post exactly the shortcut the user configured. If it's disabled we
        // must not post anything, or the keystroke would land in the frontmost app.
        guard let shortcut = desktopShortcut(for: index) else {
            logger.warning("Shortcut for space \(index) is not enabled; not switching")
            checkKeyboardShortcuts()
            return false
        }

        logger.info("Switching to space \(index)")

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logger.error("Failed to create CGEventSource")
            return false
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else {
            logger.error("Failed to create key events")
            return false
        }
        keyDown.flags = shortcut.flags
        keyUp.flags = shortcut.flags

        keyDown.post(tap: .cghidEventTap)
        // Small delay between key down and up, without blocking the main thread
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            keyUp.post(tap: .cghidEventTap)
        }

        logger.debug("Key events posted for space \(index)")
        return true
    }
}

// MARK: - Private Core Graphics APIs

// CGSConnectionID is a C `int` (32-bit), so it must be Int32, not Int.
typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: CGSConnectionID) -> CFArray?
