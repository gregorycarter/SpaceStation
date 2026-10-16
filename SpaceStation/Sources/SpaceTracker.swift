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

/// Tracks the current Space (virtual desktop) and notifies observers of changes
@MainActor
class SpaceTracker: ObservableObject {
    @Published private(set) var currentSpaceIndex: Int = 1
    @Published private(set) var spaces: [SpaceInfo] = [.placeholder]
    /// True while the active Space is a fullscreen app rather than a desktop.
    @Published private(set) var isInFullscreenSpace: Bool = false
    @Published private(set) var isTrackingAvailable: Bool = true
    @Published private(set) var hasAccessibilityPermission: Bool = false
    @Published private(set) var hasKeyboardShortcutsEnabled: Bool = false

    /// macOS only provides "Switch to Desktop N" shortcuts for Desktops 1-9.
    static let maxSwitchableSpace = 9

    var totalSpaces: Int { spaces.count }

    /// The current desktop Space (never empty; falls back to a placeholder).
    var currentSpace: SpaceInfo {
        spaces.first { $0.index == currentSpaceIndex } ?? spaces.first ?? .placeholder
    }

    private var spaceChangeObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "SpaceTracker")

    init() {
        logger.info("SpaceTracker initializing")
        checkAccessibilityPermission()
        checkKeyboardShortcuts()
        setupSpaceChangeObserver()
        updateCurrentSpace()
    }

    // MARK: - Accessibility Permission

    func checkAccessibilityPermission() {
        // Use AXIsProcessTrustedWithOptions for a fresh check (not cached)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        hasAccessibilityPermission = trusted
        logger.info("Accessibility permission check: \(trusted)")
    }

    func requestAccessibilityPermission() {
        logger.info("Requesting accessibility permission")

        // This will prompt the user to grant accessibility permission
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        hasAccessibilityPermission = trusted
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

    func resetAndRequestPermission() {
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
            await self?.requestPermissionAndOpenSettings()
        }
    }

    private func requestPermissionAndOpenSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        hasAccessibilityPermission = trusted
        logger.info("Permission after reset: \(trusted)")

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Keyboard Shortcuts Check

    func checkKeyboardShortcuts() {
        // "Switch to Desktop N" shortcuts live in com.apple.symbolichotkeys,
        // keys 118-126 (Desktop 1-9).
        let enabledCount = (1...9).filter { desktopShortcut(for: $0) != nil }.count
        hasKeyboardShortcutsEnabled = enabledCount >= 1
        logger.info("Keyboard shortcuts enabled: \(self.hasKeyboardShortcutsEnabled) (\(enabledCount)/9 shortcuts)")
    }

    /// The key and modifiers the user has configured for "Switch to Desktop N",
    /// or nil if that shortcut is disabled or can't be read.
    private func desktopShortcut(for index: Int) -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        guard (1...9).contains(index),
              let hotkeys = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let symbolicHotkeys = hotkeys["AppleSymbolicHotKeys"] as? [String: Any],
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
        return (CGKeyCode(parameters[1]), CGEventFlags(rawValue: UInt64(parameters[2])))
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

        spaces = snapshot.spaces
        currentSpaceIndex = newIndex
        isInFullscreenSpace = isFullscreen
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

        guard let display = activeDisplay(in: displays),
              let currentSpace = display["Current Space"] as? [String: Any],
              let currentID = currentSpace["ManagedSpaceID"] as? Int,
              let allSpaces = display["Spaces"] as? [[String: Any]] else {
            logger.debug("No spaces found, returning defaults")
            return fallback
        }

        // Only desktop Spaces (type 0); fullscreen apps (type 4) are excluded.
        let desktops = allSpaces.filter { ($0["type"] as? Int ?? 0) == 0 }
        guard !desktops.isEmpty else { return fallback }

        let infos = desktops.enumerated().map { offset, space in
            SpaceInfo(id: Self.stableID(for: space), index: offset + 1)
        }
        let currentIndex = desktops.firstIndex { ($0["ManagedSpaceID"] as? Int) == currentID }
            .map { $0 + 1 }
        return (infos, currentIndex)
    }

    /// With "Displays have separate Spaces" each display has its own Spaces. Use the
    /// one the user is working on (the screen with keyboard focus), not just the first.
    private func activeDisplay(in displays: [[String: Any]]) -> [String: Any]? {
        guard displays.count > 1 else { return displays.first }

        if let screen = NSScreen.main,
           let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
           let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
           let uuidString = CFUUIDCreateString(nil, uuid) as String?,
           let match = displays.first(where: {
               ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(uuidString) == .orderedSame
           }) {
            return match
        }

        return displays.first { ($0["Display Identifier"] as? String) == "Main" } ?? displays.first
    }

    /// Prefer the Space's uuid; some Spaces report an empty one, so fall back to
    /// the managed Space ID.
    private static func stableID(for space: [String: Any]) -> String {
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
        // Small delay between key down and up
        usleep(20000) // 20ms
        keyUp.post(tap: .cghidEventTap)

        logger.debug("Key events posted for space \(index)")
        return true
    }

    func cleanup() {
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
            logger.debug("Space change observer removed")
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
