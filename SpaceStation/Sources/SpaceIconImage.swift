import AppKit

/// Renders a Space's icon as an NSImage for the menu bar and menus.
enum SpaceIconImage {
    /// SF Symbol shown in the menu bar while a fullscreen app is active.
    static let fullscreenSymbol = "arrow.up.left.and.arrow.down.right"

    /// `icon` as a 16 pt image: a template SF Symbol (so it adapts to the menu bar and
    /// highlight), an emoji drawn into a colour image, or, with no icon, the Space's number
    /// as an SF Symbol such as "3.square".
    static func image(for icon: SpaceIcon?, index: Int, size: CGFloat = 16) -> NSImage {
        switch icon {
        case .symbol(let name):
            return symbol(name, size: size) ?? symbol(SpaceIcon.numberSymbol(for: index), size: size) ?? NSImage()
        case .emoji(let text):
            return emoji(text, size: size)
        case nil:
            return symbol(SpaceIcon.numberSymbol(for: index), size: size) ?? NSImage()
        }
    }

    static func symbol(_ name: String, size: CGFloat = 16, accessibilityDescription: String? = nil) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.82, weight: .regular, scale: .medium)
        let image = base.withSymbolConfiguration(configuration) ?? base
        image.isTemplate = true
        return image
    }

    static func emoji(_ text: String, size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size * 0.82)])
            let textSize = attributed.size()
            attributed.draw(at: NSPoint(x: (rect.width - textSize.width) / 2, y: (rect.height - textSize.height) / 2))
            return true
        }
        image.isTemplate = false
        return image
    }
}
