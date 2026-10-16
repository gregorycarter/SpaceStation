import XCTest
import AppKit

@MainActor
final class SpaceIconTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let space = SpaceInfo(id: "id-1", index: 1)

    override func setUp() {
        super.setUp()
        suiteName = "SpaceStationIconTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testStorageRoundTrip() {
        for icon in [SpaceIcon.symbol("briefcase"), .emoji("🔥"), .symbol("desktopcomputer")] {
            XCTAssertEqual(SpaceIcon(storageValue: icon.storageValue), icon)
        }
    }

    func testInvalidStorageValuesAreRejected() {
        XCTAssertNil(SpaceIcon(storageValue: ""))
        XCTAssertNil(SpaceIcon(storageValue: "symbol:"))
        XCTAssertNil(SpaceIcon(storageValue: "emoji:abc"))
        XCTAssertNil(SpaceIcon(storageValue: "bogus:thing"))
    }

    func testEmojiInputTakesTheFirstEmojiOnly() {
        XCTAssertEqual(SpaceIcon.emoji(from: "🔥"), .emoji("🔥"))
        XCTAssertEqual(SpaceIcon.emoji(from: "hi 🚀🔥"), .emoji("🚀"))
        XCTAssertEqual(SpaceIcon.emoji(from: "❤️"), .emoji("❤️"))
    }

    func testPlainTextAndDigitsAreNotEmoji() {
        XCTAssertNil(SpaceIcon.emoji(from: "abc"))
        XCTAssertNil(SpaceIcon.emoji(from: "123"))
        XCTAssertNil(SpaceIcon.emoji(from: "#*"))
        XCTAssertNil(SpaceIcon.emoji(from: ""))
    }

    func testNoIconByDefault() {
        let manager = SpaceNameManager(defaults: defaults)
        XCTAssertNil(manager.icon(for: space))
        XCTAssertFalse(manager.hasCustomIcon(for: space))
    }

    func testIconFollowsTheSpaceWhenItsPositionChanges() {
        let manager = SpaceNameManager(defaults: defaults)
        manager.setIcon(.symbol("briefcase"), for: space)
        XCTAssertEqual(manager.icon(for: SpaceInfo(id: "id-1", index: 5)), .symbol("briefcase"))
    }

    func testIconsPersistAndCanBeReset() {
        SpaceNameManager(defaults: defaults).setIcon(.emoji("🎧"), for: space)
        let reloaded = SpaceNameManager(defaults: defaults)
        XCTAssertEqual(reloaded.icon(for: space), .emoji("🎧"))
        reloaded.setIcon(nil, for: space)
        XCTAssertFalse(reloaded.hasCustomIcon(for: space))
        XCTAssertNil(SpaceNameManager(defaults: defaults).icon(for: space))
    }

    func testDesktopcomputerIsJustAnotherSymbolNow() {
        let manager = SpaceNameManager(defaults: defaults)
        manager.setIcon(.symbol("desktopcomputer"), for: space)
        XCTAssertEqual(manager.icon(for: space), .symbol("desktopcomputer"))
    }

    func testSuggestedSymbolsExistOnThisSystem() {
        for name in SpaceIcon.symbolChoices {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "missing symbol \(name)")
        }
        XCTAssertEqual(SpaceIcon.symbolChoices.count, 16)
        XCTAssertEqual(Set(SpaceIcon.symbolChoices).count, 16)
    }

    func testNumberSymbolsExistForEverySupportedSpace() {
        for index in 1...16 {
            XCTAssertNotNil(NSImage(systemSymbolName: SpaceIcon.numberSymbol(for: index), accessibilityDescription: nil))
        }
    }

    func testResetAllClearsNamesIconsAndLegacyData() throws {
        defaults.set(try JSONEncoder().encode([1: "Old"]), forKey: "SpaceStationNames")
        let manager = SpaceNameManager(defaults: defaults)
        manager.setName("Mail", for: space)
        manager.setIcon(.emoji("📬"), for: space)
        manager.resetAll()
        XCTAssertFalse(manager.hasCustomName(for: space))
        XCTAssertNil(manager.icon(for: space))
        XCTAssertNil(defaults.data(forKey: "SpaceStationNames"))
        let reloaded = SpaceNameManager(defaults: defaults)
        XCTAssertFalse(reloaded.hasCustomName(for: space))
        XCTAssertNil(reloaded.icon(for: space))
    }
}
