import AppKit

/// A small red dot shown on the menu bar item while an update is waiting. It sits on the corner of
/// the icon (or at the end of the name when there is no icon), like an app badge.
final class StatusItemBadge: NSView {
    static let diameter: CGFloat = 7

    /// The badge's frame for a badge on the top-right corner of `target`, nudged slightly inside so it
    /// overlaps the corner rather than floating off it. Pure so it can be tested.
    static func frame(onCornerOf target: NSRect, isFlipped: Bool) -> NSRect {
        let centerX = target.maxX - 1
        let centerY = isFlipped ? target.minY + 1 : target.maxY - 1
        return NSRect(x: centerX - diameter / 2, y: centerY - diameter / 2, width: diameter, height: diameter)
    }

    /// Adds a (hidden) badge to `button`.
    @discardableResult
    static func install(on button: NSView) -> StatusItemBadge {
        let badge = StatusItemBadge(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        badge.isHidden = true
        button.addSubview(badge)
        return badge
    }

    /// Moves the badge to the button's icon (or, with no icon, its title). Call after the button's
    /// image, title or size changes.
    func reposition(on button: NSButton, showsIcon: Bool) {
        guard let cell = button.cell as? NSButtonCell else { return }
        var target: NSRect
        if showsIcon, let image = button.image {
            // The cell's image rect can be smaller than the glyph (symbols carry padding), so use the
            // image's own size, centred where the cell draws it.
            let drawn = cell.imageRect(forBounds: button.bounds)
            target = NSRect(x: drawn.midX - image.size.width / 2, y: drawn.midY - image.size.height / 2,
                            width: image.size.width, height: image.size.height)
        } else {
            target = cell.titleRect(forBounds: button.bounds)
        }
        guard target.width > 0, target.height > 0 else { return }
        frame = Self.frame(onCornerOf: target, isFlipped: button.isFlipped)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)   // the button's own label announces the update
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = Self.diameter / 2
        layer?.backgroundColor = NSColor.systemRed.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.black.withAlphaComponent(0.25).cgColor
    }

    // Never intercept clicks meant for the menu bar item.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
