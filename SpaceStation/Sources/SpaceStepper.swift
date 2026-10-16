import Foundation

/// Every Space on the focused display in Mission Control order, fullscreen Spaces included.
///
/// Moving with the "Move left/right a space" shortcuts passes through every Space, not just
/// desktops, so reaching a desktop that has no "Switch to Desktop N" shortcut (Desktops 10+, or
/// ones the user hasn't enabled) means counting fullscreen Spaces too.
struct SpaceOrder: Equatable {
    struct Entry: Equatable {
        let managedID: Int
        /// The stable ID (`SpaceInfo.id`) if this is a desktop; nil for fullscreen Spaces.
        let desktopID: String?
    }

    let entries: [Entry]
    let currentManagedID: Int

    /// Pure parser for the `CGSCopyManagedDisplaySpaces` result (testable).
    nonisolated static func parse(displays: [[String: Any]], focusedDisplayUUID: String?) -> SpaceOrder? {
        guard let display = SpaceTracker.activeDisplay(in: displays, focusedDisplayUUID: focusedDisplayUUID),
              let current = display["Current Space"] as? [String: Any],
              let currentID = current["ManagedSpaceID"] as? Int,
              let spaces = display["Spaces"] as? [[String: Any]] else {
            return nil
        }
        let entries = spaces.compactMap { space -> Entry? in
            guard let managedID = space["ManagedSpaceID"] as? Int else { return nil }
            let isDesktop = (space["type"] as? Int ?? 0) == 0
            return Entry(managedID: managedID, desktopID: isDesktop ? SpaceTracker.stableID(for: space) : nil)
        }
        guard !entries.isEmpty else { return nil }
        return SpaceOrder(entries: entries, currentManagedID: currentID)
    }

    var currentPosition: Int? { entries.firstIndex { $0.managedID == currentManagedID } }

    func position(ofDesktop id: String) -> Int? { entries.firstIndex { $0.desktopID == id } }
}

enum SpaceStepper {
    enum Direction: Equatable { case left, right }

    struct Plan: Equatable {
        let direction: Direction
        let steps: Int
    }

    /// How to reach `desktopID` by moving one Space at a time: nil if it is already the current
    /// Space or can't be found.
    static func plan(order: SpaceOrder, to desktopID: String) -> Plan? {
        guard let from = order.currentPosition, let to = order.position(ofDesktop: desktopID), from != to else {
            return nil
        }
        return Plan(direction: to > from ? .right : .left, steps: abs(to - from))
    }
}

/// Remembers the desktop that was current before the present one, so the switcher can open on
/// it and "open, then Return" toggles between the last two Spaces.
struct SpaceHistory: Equatable {
    private(set) var previousID: String?
    private var lastID: String?

    /// Call whenever the Space changes. Pass nil while in a fullscreen Space: fullscreen Spaces
    /// don't count, so coming back from one to the desktop you left leaves the history alone.
    mutating func record(currentDesktopID: String?) {
        guard let current = currentDesktopID else { return }
        if let last = lastID, last != current { previousID = last }
        lastID = current
    }
}
