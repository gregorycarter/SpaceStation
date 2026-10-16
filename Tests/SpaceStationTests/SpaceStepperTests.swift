import XCTest

final class SpaceStepperTests: XCTestCase {
    private func space(_ id: Int, type: Int = 0, uuid: String? = nil) -> [String: Any] {
        var dict: [String: Any] = ["ManagedSpaceID": id, "type": type]
        if let uuid { dict["uuid"] = uuid }
        return dict
    }

    /// Mission Control order: Desktop A, Desktop B, a fullscreen app, Desktop C, Desktop D.
    private var display: [String: Any] {
        ["Display Identifier": "X", "Current Space": ["ManagedSpaceID": 2],
         "Spaces": [space(1, uuid: "A"), space(2, uuid: "B"), space(3, type: 4), space(4, uuid: "C"), space(5, uuid: "D")]]
    }

    private func order(current: Int = 2) -> SpaceOrder {
        var d = display
        d["Current Space"] = ["ManagedSpaceID": current]
        return SpaceOrder.parse(displays: [d], focusedDisplayUUID: nil)!
    }

    func testOrderIncludesFullscreenSpaces() {
        let o = order()
        XCTAssertEqual(o.entries.count, 5)
        XCTAssertNil(o.entries[2].desktopID)
        XCTAssertEqual(o.entries.compactMap(\.desktopID), ["A", "B", "C", "D"])
        XCTAssertEqual(o.currentPosition, 1)
    }

    func testStepsCountTheFullscreenSpaceInTheWay() {
        // From B to C there is a fullscreen Space between them: two presses, not one.
        XCTAssertEqual(SpaceStepper.plan(order: order(), to: "C"), SpaceStepper.Plan(direction: .right, steps: 2))
        XCTAssertEqual(SpaceStepper.plan(order: order(), to: "D"), SpaceStepper.Plan(direction: .right, steps: 3))
        XCTAssertEqual(SpaceStepper.plan(order: order(), to: "A"), SpaceStepper.Plan(direction: .left, steps: 1))
    }

    func testSteppingFromTheOtherSideOfTheFullscreenSpace() {
        XCTAssertEqual(SpaceStepper.plan(order: order(current: 5), to: "B"), SpaceStepper.Plan(direction: .left, steps: 3))
    }

    func testNoPlanForTheCurrentOrAnUnknownSpace() {
        XCTAssertNil(SpaceStepper.plan(order: order(), to: "B"))
        XCTAssertNil(SpaceStepper.plan(order: order(), to: "nope"))
    }

    func testCurrentSpaceBeingFullscreenStillPlansFromItsPosition() {
        XCTAssertEqual(SpaceStepper.plan(order: order(current: 3), to: "D"), SpaceStepper.Plan(direction: .right, steps: 2))
        XCTAssertEqual(SpaceStepper.plan(order: order(current: 3), to: "A"), SpaceStepper.Plan(direction: .left, steps: 2))
    }

    func testMultipleDisplaysUseTheFocusedOne() {
        let other: [String: Any] = ["Display Identifier": "Y", "Current Space": ["ManagedSpaceID": 9],
                                    "Spaces": [space(9, uuid: "P"), space(10, uuid: "Q")]]
        let o = SpaceOrder.parse(displays: [display, other], focusedDisplayUUID: "y")
        XCTAssertEqual(o?.entries.compactMap(\.desktopID), ["P", "Q"])
    }

    func testUnparseableDataGivesNoOrder() {
        XCTAssertNil(SpaceOrder.parse(displays: [], focusedDisplayUUID: nil))
        XCTAssertNil(SpaceOrder.parse(displays: [["Spaces": []]], focusedDisplayUUID: nil))
    }
}

final class SpaceHistoryTests: XCTestCase {
    func testNoPreviousUntilTheSpaceChanges() {
        var history = SpaceHistory()
        history.record(currentDesktopID: "A")
        history.record(currentDesktopID: "A")
        XCTAssertNil(history.previousID)
    }

    func testPreviousIsTheDesktopBeforeThisOne() {
        var history = SpaceHistory()
        history.record(currentDesktopID: "A")
        history.record(currentDesktopID: "B")
        XCTAssertEqual(history.previousID, "A")
        history.record(currentDesktopID: "C")
        XCTAssertEqual(history.previousID, "B")
    }

    func testOpenThenReturnTogglesBetweenTheLastTwo() {
        var history = SpaceHistory()
        history.record(currentDesktopID: "A")
        history.record(currentDesktopID: "B")
        history.record(currentDesktopID: history.previousID)   // user picks the preselected Space
        XCTAssertEqual(history.previousID, "B")
        history.record(currentDesktopID: history.previousID)
        XCTAssertEqual(history.previousID, "A")
    }

    func testFullscreenSpacesDoNotDisturbTheHistory() {
        var history = SpaceHistory()
        history.record(currentDesktopID: "A")
        history.record(currentDesktopID: "B")
        history.record(currentDesktopID: nil)    // into a fullscreen app
        XCTAssertEqual(history.previousID, "A")
        history.record(currentDesktopID: "B")    // back to the same desktop
        XCTAssertEqual(history.previousID, "A")
    }
}
