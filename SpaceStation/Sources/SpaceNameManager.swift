import Foundation
import SwiftUI
import os.log

/// Manages custom names for Spaces with persistent storage.
///
/// Names are keyed by `SpaceInfo.id` (the Space's stable identifier), not by its
/// position, so reordering or deleting Spaces doesn't move names onto other desktops.
@MainActor
class SpaceNameManager: ObservableObject {
    @Published private var spaceNames: [String: String] = [:]

    /// Keeps the menu bar item (which shows the name) from growing without bound.
    static let maxNameLength = 40

    private let storageKey = "SpaceStationNamesByID"
    /// Pre-1.1 storage: names keyed by Space position.
    private let legacyStorageKey = "SpaceStationNames"
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "SpaceNameManager")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadNames()
        logger.info("SpaceNameManager initialized with \(self.spaceNames.count) custom names")
    }

    /// Get the name for a space, or default to "Desktop N"
    func name(for space: SpaceInfo) -> String {
        spaceNames[space.id] ?? defaultName(for: space)
    }

    /// Check if a space has a custom name
    func hasCustomName(for space: SpaceInfo) -> Bool {
        spaceNames[space.id] != nil
    }

    /// Set a custom name for a space
    func setName(_ name: String, for space: SpaceInfo) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))

        if trimmed.isEmpty || trimmed == defaultName(for: space) {
            // Remove custom name if empty or matches default
            if spaceNames.removeValue(forKey: space.id) != nil {
                logger.info("Removed custom name for space \(space.index)")
            }
        } else {
            spaceNames[space.id] = trimmed
            logger.info("Set name for space \(space.index)")
        }

        saveNames()
    }

    /// Remove custom name for a space (revert to default)
    func removeName(for space: SpaceInfo) {
        if spaceNames.removeValue(forKey: space.id) != nil {
            logger.info("Removed custom name for space \(space.index)")
            saveNames()
        }
    }

    private func defaultName(for space: SpaceInfo) -> String {
        "Desktop \(space.index)"
    }

    // MARK: - Persistence

    /// One-time migration of names saved by position to names keyed by Space ID.
    /// Safe to call repeatedly; it does nothing once the legacy data is gone or
    /// until real Spaces have been detected.
    func migrateLegacyNames(using spaces: [SpaceInfo]) {
        guard spaces.first != .placeholder,
              let data = defaults.data(forKey: legacyStorageKey) else { return }

        if let legacy = try? JSONDecoder().decode([Int: String].self, from: data) {
            for space in spaces {
                if let name = legacy[space.index], spaceNames[space.id] == nil {
                    spaceNames[space.id] = name
                }
            }
            saveNames()
            logger.info("Migrated \(legacy.count) legacy names")
        } else {
            logger.error("Legacy names could not be decoded; discarding")
        }
        defaults.removeObject(forKey: legacyStorageKey)
    }

    private func loadNames() {
        guard let data = defaults.data(forKey: storageKey) else {
            logger.debug("No saved names found")
            return
        }

        do {
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
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
