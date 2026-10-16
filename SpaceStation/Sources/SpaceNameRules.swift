import Foundation

/// Shared rules for editing and saving names. Editing preserves whitespace; saving trims it.
enum SpaceNameRules {
    static let maxLength = 40

    static func limitInput(_ text: String) -> String {
        String(text.prefix(maxLength))
    }

    static func normalize(_ text: String) -> String {
        limitInput(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func defaultName(index: Int) -> String { "Desktop \(index)" }
}
