import XCTest
@testable import SpaceStation

@MainActor
final class SpaceNameManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SpaceStationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private let one = SpaceInfo(id: "id-1", index: 1)
    private let two = SpaceInfo(id: "id-2", index: 2)

    func testDefaultNameUsesPosition() {
        let manager = SpaceNameManager(defaults: defaults)
        XCTAssertEqual(manager.name(for: two), "Desktop 2")
        XCTAssertFalse(manager.hasCustomName(for: two))
    }

    func testCustomNameFollowsTheSpaceWhenItsPositionChanges() {
        let manager = SpaceNameManager(defaults: defaults)
        manager.setName("Mail", for: one)
        let movedToPositionThree = SpaceInfo(id: "id-1", index: 3)
        XCTAssertEqual(manager.name(for: movedToPositionThree), "Mail")
    }

    func testEmptyOrDefaultNameRemovesCustomName() {
        let manager = SpaceNameManager(defaults: defaults)
        manager.setName("Mail", for: one)
        manager.setName("   ", for: one)
        XCTAssertFalse(manager.hasCustomName(for: one))
        manager.setName("Mail", for: one)
        manager.setName("Desktop 1", for: one)
        XCTAssertFalse(manager.hasCustomName(for: one))
    }

    func testNamesAreTrimmedAndTruncated() {
        let manager = SpaceNameManager(defaults: defaults)
        manager.setName("  Work  ", for: one)
        XCTAssertEqual(manager.name(for: one), "Work")
        manager.setName(String(repeating: "x", count: 200), for: two)
        XCTAssertEqual(manager.name(for: two).count, SpaceNameManager.maxNameLength)
    }

    func testNamesPersistAcrossInstances() {
        SpaceNameManager(defaults: defaults).setName("Code", for: one)
        XCTAssertEqual(SpaceNameManager(defaults: defaults).name(for: one), "Code")
    }

    func testRemoveNameRevertsToDefault() {
        let manager = SpaceNameManager(defaults: defaults)
        manager.setName("Code", for: one)
        manager.removeName(for: one)
        XCTAssertEqual(manager.name(for: one), "Desktop 1")
    }

    func testLegacyPositionKeyedNamesAreMigratedOnce() throws {
        defaults.set(try JSONEncoder().encode([1: "Mail", 2: "Code"]), forKey: "SpaceStationNames")
        let manager = SpaceNameManager(defaults: defaults)
        manager.migrateLegacyNames(using: [one, two])
        XCTAssertEqual(manager.name(for: one), "Mail")
        XCTAssertEqual(manager.name(for: two), "Code")
        XCTAssertNil(defaults.data(forKey: "SpaceStationNames"), "legacy key should be removed")
        // Reordering afterwards must not re-apply the old position mapping.
        manager.migrateLegacyNames(using: [SpaceInfo(id: "id-2", index: 1), SpaceInfo(id: "id-1", index: 2)])
        XCTAssertEqual(manager.name(for: SpaceInfo(id: "id-1", index: 2)), "Mail")
    }

    func testMigrationWaitsForRealSpaces() throws {
        defaults.set(try JSONEncoder().encode([1: "Mail"]), forKey: "SpaceStationNames")
        let manager = SpaceNameManager(defaults: defaults)
        manager.migrateLegacyNames(using: [.placeholder])
        XCTAssertNotNil(defaults.data(forKey: "SpaceStationNames"))
        manager.migrateLegacyNames(using: [one])
        XCTAssertEqual(manager.name(for: one), "Mail")
    }

    func testMigrationDoesNotOverwriteExistingNames() throws {
        let manager = SpaceNameManager(defaults: defaults)
        manager.setName("New", for: one)
        defaults.set(try JSONEncoder().encode([1: "Old"]), forKey: "SpaceStationNames")
        manager.migrateLegacyNames(using: [one])
        XCTAssertEqual(manager.name(for: one), "New")
    }
}
