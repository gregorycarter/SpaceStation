import Foundation
import SwiftUI

/// Manages custom names for Spaces with persistent storage
@MainActor
class SpaceNameManager: ObservableObject {
    @Published private var spaceNames: [Int: String] = [:]

    private let storageKey = "SpaceStationNames"
    private let defaults = UserDefaults.standard

    init() {
        loadNames()
    }

    /// Get the name for a space, or default to "Desktop N"
    func name(for spaceIndex: Int) -> String {
        spaceNames[spaceIndex] ?? "Desktop \(spaceIndex)"
    }

    /// Check if a space has a custom name
    func hasCustomName(for spaceIndex: Int) -> Bool {
        spaceNames[spaceIndex] != nil
    }

    /// Set a custom name for a space
    func setName(_ name: String, for spaceIndex: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty || trimmed == "Desktop \(spaceIndex)" {
            // Remove custom name if empty or matches default
            spaceNames.removeValue(forKey: spaceIndex)
        } else {
            spaceNames[spaceIndex] = trimmed
        }

        saveNames()
    }

    /// Remove custom name for a space (revert to default)
    func removeName(for spaceIndex: Int) {
        spaceNames.removeValue(forKey: spaceIndex)
        saveNames()
    }

    /// Get all custom names
    func allCustomNames() -> [Int: String] {
        spaceNames
    }

    // MARK: - Persistence

    private func loadNames() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Int: String].self, from: data) else {
            return
        }
        spaceNames = decoded
    }

    private func saveNames() {
        guard let data = try? JSONEncoder().encode(spaceNames) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
