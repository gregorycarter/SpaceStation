import XCTest

final class SpaceNameRulesTests: XCTestCase {
    func testEditingPreservesSpacesAndSavingTrimsThem() {
        XCTAssertEqual(SpaceNameRules.limitInput("  Work \n"), "  Work \n")
        XCTAssertEqual(SpaceNameRules.normalize("  Work \n"), "Work")
    }

    func testLimitsCountCharactersWithoutSplittingEmoji() {
        let emoji = "👩🏽‍🚀"
        let text = String(repeating: emoji, count: 41)
        XCTAssertEqual(SpaceNameRules.limitInput(text), String(repeating: emoji, count: 40))
        XCTAssertEqual(SpaceNameRules.normalize("  " + text), String(repeating: emoji, count: 40))
    }
}
