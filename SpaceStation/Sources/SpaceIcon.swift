import Foundation

/// An icon shown next to a Space's name: either an SF Symbol or a single emoji.
enum SpaceIcon: Equatable {
    case symbol(String)
    case emoji(String)

    /// SF Symbols offered in the picker (all available on macOS 13). A Space with no icon shows
    /// its number instead, so there is no default symbol.
    static let symbolChoices: [String] = [
        "tray", "terminal", "briefcase", "chevron.left.forwardslash.chevron.right",
        "envelope", "calendar", "creditcard", "person.2",
        "paintpalette", "book", "music.note", "camera",
        "bubble.left", "graduationcap", "house", "flag",
    ]

    /// The symbol shown in the menu bar and menus for a Space with no icon, e.g. "3.square".
    /// (SF Symbols has number squares for 0 through 50.)
    static func numberSymbol(for index: Int) -> String { "\(index).square" }

    // MARK: Storage

    /// Stable string form for UserDefaults, e.g. "symbol:briefcase" or "emoji:🔥".
    var storageValue: String {
        switch self {
        case .symbol(let name): return "symbol:\(name)"
        case .emoji(let text): return "emoji:\(text)"
        }
    }

    init?(storageValue: String) {
        if storageValue.hasPrefix("symbol:") {
            let name = String(storageValue.dropFirst("symbol:".count))
            guard !name.isEmpty else { return nil }
            self = .symbol(name)
        } else if storageValue.hasPrefix("emoji:") {
            guard let icon = SpaceIcon.emoji(from: String(storageValue.dropFirst("emoji:".count))) else { return nil }
            self = icon
        } else {
            return nil
        }
    }

    /// Builds an emoji icon from user input: the first emoji character, or nil if there isn't one.
    static func emoji(from text: String) -> SpaceIcon? {
        for character in text {
            let isEmoji = character.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation
                    || (scalar.properties.isEmoji && scalar.value > 0x7F) // excludes plain digits and #, *
            }
            if isEmoji { return .emoji(String(character)) }
        }
        return nil
    }
}
