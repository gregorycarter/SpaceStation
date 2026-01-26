import Foundation
import Cocoa
import Combine
import os.log

/// Tracks the current Space (virtual desktop) and notifies observers of changes
@MainActor
class SpaceTracker: ObservableObject {
    @Published private(set) var currentSpaceIndex: Int = 1
    @Published private(set) var totalSpaces: Int = 1
    @Published private(set) var isTrackingAvailable: Bool = true

    private var spaceChangeObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "SpaceTracker")

    init() {
        logger.info("SpaceTracker initializing")
        setupSpaceChangeObserver()
        updateCurrentSpace()
    }

    private func setupSpaceChangeObserver() {
        // Observe Space changes via NSWorkspace
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
        // Get the display spaces using the managed display spaces
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
                return type == 0 // Type 0 is regular desktop
            }

            // Find index of current space in filtered list
            for (index, space) in desktopSpaces.enumerated() {
                if let id = space["ManagedSpaceID"] as? Int, id == spaceID {
                    return (index: index + 1, total: max(desktopSpaces.count, 1))
                }
            }

            // Current space might be fullscreen - still return desktop count
            if !desktopSpaces.isEmpty {
                return (index: 1, total: desktopSpaces.count)
            }
        }

        logger.debug("No spaces found, returning defaults")
        return (1, 1)
    }

    /// Switch to a specific space by index
    func switchToSpace(_ index: Int) {
        guard index >= 1 && index <= 9 else {
            logger.warning("Invalid space index: \(index)")
            return
        }

        logger.info("Switching to space \(index)")

        // Use keyboard shortcut simulation to switch spaces
        // Control + [number] is the default macOS shortcut
        let keyCode = keyCodeForNumber(index)

        let source = CGEventSource(stateID: .hidSystemState)

        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = .maskControl
            keyDown.post(tap: .cghidEventTap)
        }

        // Small delay between key down and up
        usleep(10000) // 10ms

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = .maskControl
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func keyCodeForNumber(_ number: Int) -> CGKeyCode {
        // Key codes for number keys 1-9 on US keyboard
        let keyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // 1-9
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
// These are private APIs used to query Space information

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: Int) -> CFArray?
