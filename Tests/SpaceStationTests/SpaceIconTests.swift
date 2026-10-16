import XCTest
@testable import SpaceStation

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
        for icon in [SpaceIcon.symbol("briefcase"), .emoji("🔥"), .default] {
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

    func testDefaultIconWhenNoneChosen() {
        let manager = SpaceNameManager(defaults: defaults)
        XCTAssertEqual(manager.icon(for: space), .default)
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
        XCTAssertEqual(SpaceNameManager(defaults: defaults).icon(for: space), .default)
    }

    func testChoosingTheDefaultIconClearsTheCustomOne() {
        let manager = SpaceNameManager(defaults: defaults)
        manager.setIcon(.symbol("star"), for: space)
        manager.setIcon(.default, for: space)
        XCTAssertFalse(manager.hasCustomIcon(for: space))
    }
}
