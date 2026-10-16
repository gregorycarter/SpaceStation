import Foundation

/// What the menu bar item shows for the current Space.
enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case iconAndName, iconOnly, nameOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .iconAndName: return "Icon and Name"
        case .iconOnly: return "Icon Only"
        case .nameOnly: return "Name Only"
        }
    }

    var showsIcon: Bool { self != .nameOnly }
    var showsName: Bool { self != .iconOnly }
}

enum MenuBarFormat {
    static let nameLimit = 20

    /// Shortens a name longer than `nameLimit` characters to that many characters plus "…".
    static func displayName(_ name: String, shorten: Bool) -> String {
        guard shorten, name.count > nameLimit else { return name }
        let head = String(name.prefix(nameLimit)).trimmingCharacters(in: .whitespaces)
        return head + "…"
    }
}
