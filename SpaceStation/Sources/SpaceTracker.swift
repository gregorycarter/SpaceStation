import Foundation
import Cocoa
import Combine

/// Tracks the current Space (virtual desktop) and notifies observers of changes
@MainActor
class SpaceTracker: ObservableObject {
    @Published private(set) var currentSpaceIndex: Int = 1
    @Published private(set) var totalSpaces: Int = 1

    private var spaceChangeObserver: NSObjectProtocol?

    init() {
        setupSpaceChangeObserver()
        updateCurrentSpace()
    }

    deinit {
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
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
    }

    private func updateCurrentSpace() {
        // Get current space information using Core Graphics private APIs
        // We use the CGSConnection to query space information
        let spaceInfo = getCurrentSpaceInfo()
        currentSpaceIndex = spaceInfo.index
        totalSpaces = spaceInfo.total
    }

    private func getCurrentSpaceInfo() -> (index: Int, total: Int) {
        // Use CGWindowListCopyWindowInfo to determine current space
        // This is a workaround since direct Space APIs are private

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return (1, 1)
        }

        // Get the display spaces using the managed display spaces
        let conn = CGSMainConnectionID()

        if let spaces = CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] {
            for display in spaces {
                if let currentSpace = display["Current Space"] as? [String: Any],
                   let spaceID = currentSpace["ManagedSpaceID"] as? Int,
                   let allSpaces = display["Spaces"] as? [[String: Any]] {

                    // Find index of current space
                    for (index, space) in allSpaces.enumerated() {
                        if let id = space["ManagedSpaceID"] as? Int, id == spaceID {
                            // Filter out fullscreen spaces (type 4)
                            let desktopSpaces = allSpaces.filter { ($0["type"] as? Int) != 4 }
                            let desktopIndex = desktopSpaces.firstIndex { ($0["ManagedSpaceID"] as? Int) == spaceID }
                            return (index: (desktopIndex ?? 0) + 1, total: desktopSpaces.count)
                        }
                    }
                }
            }
        }

        return (1, 1)
    }

    /// Switch to a specific space by index
    func switchToSpace(_ index: Int) {
        guard index >= 1 && index <= totalSpaces else { return }

        // Use keyboard shortcut simulation to switch spaces
        // Control + [number] is the default macOS shortcut
        let keyCode = keyCodeForNumber(index)

        let source = CGEventSource(stateID: .hidSystemState)

        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = .maskControl
            keyDown.post(tap: .cghidEventTap)
        }

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = .maskControl
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func keyCodeForNumber(_ number: Int) -> CGKeyCode {
        // Key codes for number keys 1-9
        let keyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // 1-9
        guard number >= 1 && number <= 9 else { return 18 }
        return keyCodes[number - 1]
    }
}

// MARK: - Private Core Graphics APIs
// These are private APIs used to query Space information

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: Int) -> CFArray?
