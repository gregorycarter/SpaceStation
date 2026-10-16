import XCTest

final class SwitcherLayoutTests: XCTestCase {
    func testColumnsAndRows() {
        XCTAssertEqual(SwitcherLayout.columns(for: 1), 1)
        XCTAssertEqual(SwitcherLayout.columns(for: 7), 7)
        XCTAssertEqual(SwitcherLayout.columns(for: 8), 8)
        XCTAssertEqual(SwitcherLayout.columns(for: 16), 8)
        XCTAssertEqual(SwitcherLayout.rows(for: 8), 1)
        XCTAssertEqual(SwitcherLayout.rows(for: 9), 2)
        XCTAssertEqual(SwitcherLayout.rows(for: 16), 2)
    }

    func testPanelWidthsMatchTheDesignSpec() {
        XCTAssertEqual(SwitcherLayout.panelWidth(count: 7, cardWidth: 112), 828)
        XCTAssertEqual(SwitcherLayout.panelWidth(count: 16, cardWidth: 112), 944)
    }

    func testCardWidthShrinksOnlyWhenTheScreenIsTooNarrow() {
        XCTAssertEqual(SwitcherLayout.cardWidth(count: 16, availableWidth: 2560), 112)
        XCTAssertEqual(SwitcherLayout.cardWidth(count: 16, availableWidth: 1000), 112) // 944 fits in 1000-40
        let narrow = SwitcherLayout.cardWidth(count: 16, availableWidth: 900)
        XCTAssertLessThan(narrow, 112)
        XCTAssertGreaterThanOrEqual(narrow, 96)
        XCTAssertLessThanOrEqual(SwitcherLayout.panelWidth(count: 16, cardWidth: narrow), 900 - 40)
        XCTAssertEqual(SwitcherLayout.cardWidth(count: 16, availableWidth: 500), 96) // never below the minimum
    }

    func testLeftRightWrapAcrossAllCards() {
        XCTAssertEqual(SwitcherLayout.move(from: 0, direction: .left, count: 7), 6)
        XCTAssertEqual(SwitcherLayout.move(from: 6, direction: .right, count: 7), 0)
        XCTAssertEqual(SwitcherLayout.move(from: 3, direction: .right, count: 16), 4)
        XCTAssertEqual(SwitcherLayout.move(from: 7, direction: .right, count: 16), 8) // runs on into row two
    }

    func testUpDownMoveBetweenRowsInTheSameColumn() {
        XCTAssertEqual(SwitcherLayout.move(from: 2, direction: .down, count: 16), 10)
        XCTAssertEqual(SwitcherLayout.move(from: 10, direction: .up, count: 16), 2)
        XCTAssertEqual(SwitcherLayout.move(from: 10, direction: .down, count: 16), 2) // wraps to the top
        XCTAssertEqual(SwitcherLayout.move(from: 2, direction: .up, count: 16), 10)   // wraps to the bottom
    }

    func testDownIntoAShorterLastRowClampsToTheLastCard() {
        // 11 Spaces: the second row only has columns 0-2.
        XCTAssertEqual(SwitcherLayout.move(from: 6, direction: .down, count: 11), 10)
        XCTAssertEqual(SwitcherLayout.move(from: 1, direction: .down, count: 11), 9)
    }

    func testUpDownDoNothingWithOneRow() {
        XCTAssertEqual(SwitcherLayout.move(from: 3, direction: .down, count: 7), 3)
        XCTAssertEqual(SwitcherLayout.move(from: 3, direction: .up, count: 7), 3)
    }

    func testEmptyAndOutOfRangeAreSafe() {
        XCTAssertEqual(SwitcherLayout.move(from: 0, direction: .right, count: 0), 0)
        XCTAssertEqual(SwitcherLayout.move(from: 99, direction: .left, count: 3), 1)
    }

    func testInitialSelectionPrefersThePreviousSpace() {
        let ids = ["a", "b", "c", "d"]
        XCTAssertEqual(SwitcherLayout.initialSelection(ids: ids, currentID: "c", previousID: "a"), 0)
        XCTAssertEqual(SwitcherLayout.initialSelection(ids: ids, currentID: "c", previousID: nil), 2)
        XCTAssertEqual(SwitcherLayout.initialSelection(ids: ids, currentID: "c", previousID: "c"), 2)
        XCTAssertEqual(SwitcherLayout.initialSelection(ids: ids, currentID: "c", previousID: "gone"), 2)
        XCTAssertEqual(SwitcherLayout.initialSelection(ids: ids, currentID: nil, previousID: nil), 0)
        XCTAssertEqual(SwitcherLayout.initialSelection(ids: ids, currentID: nil, previousID: "b"), 1) // in a fullscreen Space
    }
}

final class TypeSelectTests: XCTestCase {
    func testPrefixBuildsWithinTheTimeoutAndResetsAfter() {
        var buffer = TypeSelectBuffer()
        XCTAssertEqual(buffer.append("k", at: 0.0), "k")
        XCTAssertEqual(buffer.append("n", at: 0.5), "kn")
        XCTAssertEqual(buffer.append("i", at: 1.4), "kni")      // 0.9 s after the last key: still one prefix
        XCTAssertEqual(buffer.append("p", at: 2.6), "p")         // more than a second later: starts over
        buffer.reset()
        XCTAssertEqual(buffer.text, "")
    }

    func testFirstMatchIgnoresCaseAndDiacritics() {
        let names = ["Inbox", "Terminal", "Kasb", "Knightian", "Éclair"]
        XCTAssertEqual(TypeSelectBuffer.firstMatch(prefix: "k", in: names), 2)
        XCTAssertEqual(TypeSelectBuffer.firstMatch(prefix: "KN", in: names), 3)
        XCTAssertEqual(TypeSelectBuffer.firstMatch(prefix: "ecl", in: names), 4)
        XCTAssertNil(TypeSelectBuffer.firstMatch(prefix: "zzz", in: names))
        XCTAssertNil(TypeSelectBuffer.firstMatch(prefix: "", in: names))
    }

    func testMatchMustBeAPrefixNotASubstring() {
        XCTAssertNil(TypeSelectBuffer.firstMatch(prefix: "box", in: ["Inbox"]))
    }
}

final class MenuBarFormatTests: XCTestCase {
    func testShortNamesAreUntouched() {
        XCTAssertEqual(MenuBarFormat.displayName("Inbox", shorten: true), "Inbox")
        XCTAssertEqual(MenuBarFormat.displayName(String(repeating: "a", count: 20), shorten: true), String(repeating: "a", count: 20))
    }

    func testLongNamesAreShortenedToTwentyCharactersPlusAnEllipsis() {
        let result = MenuBarFormat.displayName("Client — Northwind Traders Limited", shorten: true)
        XCTAssertEqual(result, "Client — Northwind T…")
        XCTAssertEqual(result.count, 21)
    }

    func testTrailingSpaceBeforeTheEllipsisIsTrimmed() {
        XCTAssertEqual(MenuBarFormat.displayName("Quarterly Planning Q4 Review", shorten: true), "Quarterly Planning Q…")
        XCTAssertEqual(MenuBarFormat.displayName("Quarterly Planning  and more", shorten: true), "Quarterly Planning…")
    }

    func testShorteningCanBeTurnedOff() {
        let name = String(repeating: "x", count: 40)
        XCTAssertEqual(MenuBarFormat.displayName(name, shorten: false), name)
    }

    func testDisplayModes() {
        XCTAssertTrue(MenuBarDisplay.iconAndName.showsIcon && MenuBarDisplay.iconAndName.showsName)
        XCTAssertTrue(MenuBarDisplay.iconOnly.showsIcon && !MenuBarDisplay.iconOnly.showsName)
        XCTAssertTrue(!MenuBarDisplay.nameOnly.showsIcon && MenuBarDisplay.nameOnly.showsName)
    }
}
