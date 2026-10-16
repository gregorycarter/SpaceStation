import Foundation

/// A desktop's stable ID follows reordering; its one-based Mission Control index does not.
struct SpaceInfo: Identifiable, Equatable {
    let id: String
    let index: Int

    static let placeholder = SpaceInfo(id: "placeholder", index: 1)
}

/// Both views of one decoded WindowServer display. Either may be absent for malformed data.
struct SpaceSnapshot {
    struct Desktops {
        let spaces: [SpaceInfo]
        /// Nil while a fullscreen Space is active.
        let currentIndex: Int?

        static let placeholder = Desktops(spaces: [.placeholder], currentIndex: 1)
    }

    let desktops: Desktops?
    let order: SpaceOrder?

    static func parse(displays: [[String: Any]], focusedDisplayUUID: String?) -> SpaceSnapshot? {
        guard let display = activeDisplay(in: displays, focusedDisplayUUID: focusedDisplayUUID),
              let current = display["Current Space"] as? [String: Any],
              let currentID = current["ManagedSpaceID"] as? Int,
              let spaces = display["Spaces"] as? [[String: Any]] else { return nil }

        // Keep entries with a missing managed ID for desktop naming, but omit them from stepping.
        // Those are intentionally different fallbacks inherited from the original parsers.
        var desktops: [SpaceInfo] = []
        var entries: [SpaceOrder.Entry] = []
        var currentIndex: Int?
        for space in spaces {
            let managedID = space["ManagedSpaceID"] as? Int
            let desktopID = (space["type"] as? Int ?? 0) == 0 ? stableID(for: space) : nil
            if let desktopID {
                let index = desktops.count + 1
                desktops.append(SpaceInfo(id: desktopID, index: index))
                if currentIndex == nil, managedID == currentID { currentIndex = index }
            }
            if let managedID {
                entries.append(SpaceOrder.Entry(managedID: managedID, desktopID: desktopID))
            }
        }
        return SpaceSnapshot(
            desktops: desktops.isEmpty ? nil : Desktops(spaces: desktops, currentIndex: currentIndex),
            order: entries.isEmpty ? nil : SpaceOrder(entries: entries, currentManagedID: currentID))
    }

    private static func activeDisplay(in displays: [[String: Any]], focusedDisplayUUID: String?) -> [String: Any]? {
        guard displays.count > 1 else { return displays.first }
        if let focusedDisplayUUID,
           let match = displays.first(where: {
               ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(focusedDisplayUUID) == .orderedSame
           }) { return match }
        return displays.first { ($0["Display Identifier"] as? String) == "Main" } ?? displays.first
    }

    static func stableID(for space: [String: Any]) -> String {
        if let uuid = space["uuid"] as? String, !uuid.isEmpty { return uuid }
        return "managed-\(space["ManagedSpaceID"] as? Int ?? 0)"
    }
}
