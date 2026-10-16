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

    /// Fixed card height: 12 top padding + 46 icon tile + 6 + 30 (two lines of name) + 6 + 4 dot + 6 bottom.
    static let cardHeight: CGFloat = 110
    /// Keyboard hints row: hairline + 8 top padding + one line of 11 pt text + 6 bottom.
    static let footerHeight: CGFloat = 30

    static func panelHeight(count: Int, showsFooter: Bool) -> CGFloat {
        let rows = CGFloat(rows(for: count))
        return 2 * panelPadding + rows * cardHeight + (rows - 1) * cardGap + (showsFooter ? footerHeight : 0)
    }

    /// The card under `point`, given in the panel's top-left-origin coordinates, or nil if the point
    /// is in the padding, a gap, the footer, or past the last card.
    static func cardIndex(at point: CGPoint, count: Int, cardWidth: CGFloat) -> Int? {
        let x = point.x - panelPadding
        let y = point.y - panelPadding
        guard x >= 0, y >= 0 else { return nil }
        let column = Int(x / (cardWidth + cardGap))
        let row = Int(y / (cardHeight + cardGap))
        guard x - CGFloat(column) * (cardWidth + cardGap) <= cardWidth,
              y - CGFloat(row) * (cardHeight + cardGap) <= cardHeight,
              column < columns(for: count), row < rows(for: count) else { return nil }
        let index = row * columns(for: count) + column
        return index < count ? index : nil
    }

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

/// Where the switcher panel appears.
enum SwitcherAnchor: Equatable {
    case centered
    /// Next to this screen corner (opened by the hot corner with "Next to the corner" selected).
    case corner(HotCorner)
}

enum SwitcherPlacement {
    static let sideInset: CGFloat = 8
    /// Below the menu bar when anchored to a top corner.
    static let topCornerGap: CGFloat = 6
    /// Above the Dock or screen edge when anchored to a bottom corner.
    static let bottomCornerGap: CGFloat = 8
    /// Below the menu bar when centred (hotkey, menu, or "Centered on screen").
    static let centeredGap: CGFloat = 40

    /// The panel's frame in global (bottom-left origin) coordinates, within `visibleFrame`, the
    /// area of the pointer's screen that excludes the menu bar and Dock.
    static func frame(size: CGSize, visibleFrame: CGRect, anchor: SwitcherAnchor) -> CGRect {
        let centeredX = visibleFrame.midX - size.width / 2
        var origin = CGPoint(x: centeredX, y: visibleFrame.maxY - centeredGap - size.height)

        if case .corner(let corner) = anchor {
            switch corner {
            case .off: break
            case .topLeft:
                origin = CGPoint(x: visibleFrame.minX + sideInset, y: visibleFrame.maxY - topCornerGap - size.height)
            case .topRight:
                origin = CGPoint(x: visibleFrame.maxX - sideInset - size.width, y: visibleFrame.maxY - topCornerGap - size.height)
            case .bottomLeft:
                origin = CGPoint(x: visibleFrame.minX + sideInset, y: visibleFrame.minY + bottomCornerGap)
            case .bottomRight:
                origin = CGPoint(x: visibleFrame.maxX - sideInset - size.width, y: visibleFrame.minY + bottomCornerGap)
            }
        }

        // Never hang off the screen: if the panel is wider than the space, centre it.
        if size.width > visibleFrame.width - 2 * sideInset { origin.x = centeredX }
        return CGRect(origin: origin, size: size)
    }
}
