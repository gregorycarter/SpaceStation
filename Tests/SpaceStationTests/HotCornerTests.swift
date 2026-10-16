import XCTest

final class HotCornerTests: XCTestCase {
    /// One 2560x1440 display at the origin.
    private let single = [CGRect(x: 0, y: 0, width: 2560, height: 1440)]

    func testEachCornerIsDetectedOnASingleDisplay() {
        XCTAssertTrue(HotCorner.topRight.contains(CGPoint(x: 2559, y: 1439), screens: single))
        XCTAssertTrue(HotCorner.topRight.contains(CGPoint(x: 2560, y: 1440), screens: single))
        XCTAssertTrue(HotCorner.topLeft.contains(CGPoint(x: 0, y: 1439), screens: single))
        XCTAssertTrue(HotCorner.bottomLeft.contains(CGPoint(x: 1, y: 1), screens: single))
        XCTAssertTrue(HotCorner.bottomRight.contains(CGPoint(x: 2559, y: 0), screens: single))
    }

    func testOnlyTheChosenCornerTriggers() {
        let topRight = CGPoint(x: 2559, y: 1439)
        XCTAssertFalse(HotCorner.topLeft.contains(topRight, screens: single))
        XCTAssertFalse(HotCorner.bottomRight.contains(topRight, screens: single))
        XCTAssertFalse(HotCorner.off.contains(topRight, screens: single))
    }

    func testNearbyButNotInTheCornerDoesNotTrigger() {
        XCTAssertFalse(HotCorner.topRight.contains(CGPoint(x: 2500, y: 1439), screens: single)) // along the top edge
        XCTAssertFalse(HotCorner.topRight.contains(CGPoint(x: 2559, y: 1300), screens: single)) // down the right edge
        XCTAssertFalse(HotCorner.topRight.contains(CGPoint(x: 1280, y: 720), screens: single))  // middle
    }

    func testCornersTouchingAnotherDisplayAreIgnored() {
        // Two same-height displays side by side: the left one's top-right corner is just a crossing point.
        let left = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let right = CGRect(x: 2560, y: 0, width: 1920, height: 1440)
        let screens = [left, right]
        XCTAssertFalse(HotCorner.topRight.contains(CGPoint(x: 2559, y: 1439), screens: screens))
        // ...but its top-left (outer) corner and the right display's top-right still work.
        XCTAssertTrue(HotCorner.topLeft.contains(CGPoint(x: 0, y: 1439), screens: screens))
        XCTAssertTrue(HotCorner.topRight.contains(CGPoint(x: 4479, y: 1439), screens: screens))
    }

    func testCornerAboveAShorterNeighbourIsStillUsable() {
        // The right display is shorter, so nothing is beside the left display's top-right corner
        // and the pointer cannot cross there: it is a real, exposed corner.
        let left = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let right = CGRect(x: 2560, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(HotCorner.topRight.contains(CGPoint(x: 2559, y: 1439), screens: [left, right]))
    }

    func testStackedDisplaysIgnoreTheSharedEdge() {
        let lower = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let upper = CGRect(x: 0, y: 1440, width: 2560, height: 1440)
        XCTAssertFalse(HotCorner.topRight.contains(CGPoint(x: 2559, y: 1439), screens: [lower, upper]))
        XCTAssertTrue(HotCorner.topRight.contains(CGPoint(x: 2559, y: 2879), screens: [lower, upper]))
    }

    func testPointsOutsideEveryScreenNeverTrigger() {
        XCTAssertFalse(HotCorner.topRight.contains(CGPoint(x: 5000, y: 5000), screens: single))
        XCTAssertFalse(HotCorner.topRight.contains(CGPoint(x: 2559, y: 1439), screens: []))
    }
}
