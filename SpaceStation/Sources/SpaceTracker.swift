import Foundation
import Cocoa
import Combine
import os.log
import ApplicationServices

/// Tracks the current Space (virtual desktop) and notifies observers of changes
@MainActor
class SpaceTracker: ObservableObject {
    @Published private(set) var currentSpaceIndex: Int = 1
    @Published private(set) var totalSpaces: Int = 1
    @Published private(set) var isTrackingAvailable: Bool = true
    @Published private(set) var hasAccessibilityPermission: Bool = false
    @Published private(set) var hasKeyboardShortcutsEnabled: Bool = false

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

        // Reset TCC entry for this app (requires the app to be re-added)
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", "Accessibility", "com.gregorycarter.SpaceStation"]
        try? task.run()
        task.waitUntilExit()

        // Small delay to let TCC process the reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // Now request permission fresh
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            self?.hasAccessibilityPermission = trusted
            self?.logger.info("Permission after reset: \(trusted)")

            // Open settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
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
        let spaceInfo = getCurrentSpaceInfo()

        if spaceInfo.index != currentSpaceIndex || spaceInfo.total != totalSpaces {
            logger.info("Space changed: index=\(spaceInfo.index), total=\(spaceInfo.total)")
        }

        currentSpaceIndex = spaceInfo.index
        totalSpaces = spaceInfo.total
    }

    private func getCurrentSpaceInfo() -> (index: Int, total: Int) {
        let conn = CGSMainConnectionID()

        guard conn != 0 else {
            logger.warning("Failed to get CGS connection ID")
            isTrackingAvailable = false
            return (1, 1)
        }

        guard let spacesRef = CGSCopyManagedDisplaySpaces(conn),
              let spaces = spacesRef as? [[String: Any]] else {
            logger.warning("Failed to get managed display spaces")
            isTrackingAvailable = false
            return (1, 1)
        }

        isTrackingAvailable = true

        for display in spaces {
            guard let currentSpace = display["Current Space"] as? [String: Any],
                  let spaceID = currentSpace["ManagedSpaceID"] as? Int,
                  let allSpaces = display["Spaces"] as? [[String: Any]] else {
                continue
            }

            // Filter out fullscreen spaces (type 4) and dashboard (type 2)
            let desktopSpaces = allSpaces.filter { space in
                guard let type = space["type"] as? Int else { return true }
                return type == 0
            }

            for (index, space) in desktopSpaces.enumerated() {
                if let id = space["ManagedSpaceID"] as? Int, id == spaceID {
                    return (index: index + 1, total: max(desktopSpaces.count, 1))
                }
            }

            if !desktopSpaces.isEmpty {
                return (index: 1, total: desktopSpaces.count)
            }
        }

        logger.debug("No spaces found, returning defaults")
        return (1, 1)
    }

    // MARK: - Space Switching

    /// Switch to a specific space by index
    /// Returns true if the switch was attempted, false if permissions are missing
    @discardableResult
    func switchToSpace(_ index: Int) -> Bool {
        guard index >= 1 && index <= 9 else {
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
