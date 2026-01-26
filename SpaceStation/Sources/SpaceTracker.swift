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

    private var spaceChangeObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "SpaceTracker")

    init() {
        logger.info("SpaceTracker initializing")
        checkAccessibilityPermission()
        setupSpaceChangeObserver()
        updateCurrentSpace()
    }

    // MARK: - Accessibility Permission

    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        logger.info("Accessibility permission: \(self.hasAccessibilityPermission)")
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

        logger.info("Switching to space \(index)")

        // Use keyboard shortcut simulation to switch spaces
        // Control + [number] is the macOS shortcut (must be enabled in System Settings)
        let keyCode = keyCodeForNumber(index)

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logger.error("Failed to create CGEventSource")
            return false
        }

        // Key down with Control modifier
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else {
            logger.error("Failed to create key down event")
            return false
        }
        keyDown.flags = .maskControl
        keyDown.post(tap: .cghidEventTap)

        // Small delay between key down and up
        usleep(20000) // 20ms

        // Key up with Control modifier
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            logger.error("Failed to create key up event")
            return false
        }
        keyUp.flags = .maskControl
        keyUp.post(tap: .cghidEventTap)

        logger.debug("Key events posted for space \(index)")
        return true
    }

    private func keyCodeForNumber(_ number: Int) -> CGKeyCode {
        // Key codes for number keys 1-9 on US keyboard
        let keyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        guard number >= 1 && number <= 9 else { return 18 }
        return keyCodes[number - 1]
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

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: Int) -> CFArray?
