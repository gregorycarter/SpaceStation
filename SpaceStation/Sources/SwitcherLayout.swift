import CoreGraphics
import Foundation

/// Pure layout and keyboard-navigation rules for the switcher grid (see the redesign handoff).
enum SwitcherLayout {
    static let maxColumns = 8
    static let cardGap: CGFloat = 4
    static let panelPadding: CGFloat = 10
    static let preferredCardWidth: CGFloat = 112
    static let minimumCardWidth: CGFloat = 96
    /// Space kept free of the screen edges when fitting the panel.
    static let screenMargin: CGFloat = 40

    static func columns(for count: Int) -> Int { max(1, min(count, maxColumns)) }

    static func rows(for count: Int) -> Int {
        guard count > 0 else { return 1 }
        return (count + maxColumns - 1) / maxColumns
    }

    static func panelWidth(count: Int, cardWidth: CGFloat) -> CGFloat {
        let columns = CGFloat(columns(for: count))
        return columns * cardWidth + (columns - 1) * cardGap + 2 * panelPadding
    }

    /// 112 pt cards, shrunk toward 96 pt when the panel would not fit within the visible screen
    /// width (less a margin).
    static func cardWidth(count: Int, availableWidth: CGFloat) -> CGFloat {
        let available = availableWidth - screenMargin
        if panelWidth(count: count, cardWidth: preferredCardWidth) <= available { return preferredCardWidth }
        let columns = CGFloat(columns(for: count))
        let fitted = ((available - 2 * panelPadding - (columns - 1) * cardGap) / columns).rounded(.down)
        return max(minimumCardWidth, min(preferredCardWidth, fitted))
    }

    enum Direction { case left, right, up, down }

    /// The card selected after pressing an arrow key. Left/right step through all cards and wrap;
    /// up/down move between rows in the same column (clamping onto a shorter last row, and
    /// wrapping from the last row to the first). With a single row, up/down do nothing.
    static func move(from index: Int, direction: Direction, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let index = min(max(index, 0), count - 1)
        switch direction {
        case .left: return (index - 1 + count) % count
        case .right: return (index + 1) % count
        case .up, .down:
            let columns = columns(for: count)
            let rows = rows(for: count)
            guard rows > 1 else { return index }
            let column = index % columns
            let row = index / columns
            let newRow = direction == .down ? (row + 1) % rows : (row - 1 + rows) % rows
            return min(newRow * columns + column, count - 1)
        }
    }

    /// Which card is selected when the panel opens: the previously active Space, so opening and
    /// pressing Return toggles between the last two Spaces; otherwise the current one.
    static func initialSelection(ids: [String], currentID: String?, previousID: String?) -> Int {
        if let previousID, previousID != currentID, let index = ids.firstIndex(of: previousID) { return index }
        if let currentID, let index = ids.firstIndex(of: currentID) { return index }
        return 0
    }
}

/// Type-to-select: letters typed within a second of each other build a prefix, and the
/// selection jumps to the first name starting with it.
struct TypeSelectBuffer {
    static let timeout: TimeInterval = 1.0

    private(set) var text = ""
    private var lastTyped: TimeInterval?

    mutating func append(_ characters: String, at time: TimeInterval) -> String {
        if let lastTyped, time - lastTyped > Self.timeout { text = "" }
        text += characters
        lastTyped = time
        return text
    }

    mutating func reset() {
        text = ""
        lastTyped = nil
    }

    /// First name starting with `prefix`, ignoring case and diacritics.
    static func firstMatch(prefix: String, in names: [String]) -> Int? {
        guard !prefix.isEmpty else { return nil }
        return names.firstIndex {
            $0.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        }
    }
}
