import SwiftUI

/// An icon shown next to a Space's name: either an SF Symbol or a single emoji.
enum SpaceIcon: Equatable {
    case symbol(String)
    case emoji(String)

    static let `default` = SpaceIcon.symbol("desktopcomputer")

    /// SF Symbols offered in the picker (all available on macOS 13).
    static let symbolChoices: [String] = [
        "desktopcomputer", "briefcase", "hammer", "terminal", "envelope", "message",
        "calendar", "doc.text", "book", "globe", "music.note", "gamecontroller",
        "camera", "paintbrush", "chart.bar", "cart", "graduationcap", "house",
        "heart", "star", "bolt", "cloud", "folder", "lightbulb",
    ]

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

/// Renders a `SpaceIcon` at a given size.
struct SpaceIconView: View {
    let icon: SpaceIcon
    var size: CGFloat = 24

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.8))
                .frame(width: size, height: size)
        case .emoji(let text):
            Text(text)
                .font(.system(size: size * 0.85))
                .frame(width: size, height: size)
        }
    }
}
