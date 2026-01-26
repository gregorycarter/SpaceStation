import Foundation
import SwiftUI
import os.log

/// Manages custom names for Spaces with persistent storage
@MainActor
class SpaceNameManager: ObservableObject {
    @Published private var spaceNames: [Int: String] = [:]

    private let storageKey = "SpaceStationNames"
    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "SpaceNameManager")

    init() {
        loadNames()
        logger.info("SpaceNameManager initialized with \(self.spaceNames.count) custom names")
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
            if spaceNames.removeValue(forKey: spaceIndex) != nil {
                logger.info("Removed custom name for space \(spaceIndex)")
            }
        } else {
            spaceNames[spaceIndex] = trimmed
            logger.info("Set name for space \(spaceIndex): \(trimmed)")
        }

        saveNames()
    }

    /// Remove custom name for a space (revert to default)
    func removeName(for spaceIndex: Int) {
        if spaceNames.removeValue(forKey: spaceIndex) != nil {
            logger.info("Removed custom name for space \(spaceIndex)")
            saveNames()
        }
    }

    /// Get all custom names
    func allCustomNames() -> [Int: String] {
        spaceNames
    }

    // MARK: - Persistence

    private func loadNames() {
        guard let data = defaults.data(forKey: storageKey) else {
            logger.debug("No saved names found")
            return
        }

        do {
            let decoded = try JSONDecoder().decode([Int: String].self, from: data)
            spaceNames = decoded
            logger.debug("Loaded \(decoded.count) saved names")
        } catch {
            logger.error("Failed to decode saved names: \(error.localizedDescription)")
        }
    }

    private func saveNames() {
        do {
            let data = try JSONEncoder().encode(spaceNames)
            defaults.set(data, forKey: storageKey)
            logger.debug("Saved \(self.spaceNames.count) names")
        } catch {
            logger.error("Failed to encode names for saving: \(error.localizedDescription)")
        }
    }
}
