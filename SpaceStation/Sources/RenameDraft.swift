import Foundation

/// The in-progress edit in the rename popover. Pure so its rules can be tested.
struct RenameDraft: Equatable {
    let originalName: String        // the custom name, "" if the Space uses the macOS default
    let originalIcon: SpaceIcon?
    var name: String
    var icon: SpaceIcon?

    init(name: String, icon: SpaceIcon?) {
        originalName = name
        originalIcon = icon
        self.name = name
        self.icon = icon
    }

    /// The name that will be saved: trimmed and limited to the maximum length. Empty means "use the
    /// macOS default name".
    var normalizedName: String {
        SpaceNameRules.normalize(name)
    }

    /// Rename is only enabled once something differs from what was there.
    var isChanged: Bool { normalizedName != originalName || icon != originalIcon }

    mutating func setName(_ text: String) {
        name = SpaceNameRules.limitInput(text)
    }
}
