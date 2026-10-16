import XCTest
@testable import SpaceStation

final class SpaceParsingTests: XCTestCase {
    private func space(_ id: Int, type: Int = 0, uuid: String? = nil) -> [String: Any] {
        var dict: [String: Any] = ["ManagedSpaceID": id, "type": type]
        if let uuid { dict["uuid"] = uuid }
        return dict
    }

    private func display(_ identifier: String, current: Int, spaces: [[String: Any]]) -> [String: Any] {
        ["Display Identifier": identifier, "Current Space": ["ManagedSpaceID": current], "Spaces": spaces]
    }

    func testDesktopsGetOneBasedIndicesAndStableIDs() throws {
        let d = display("A", current: 2, spaces: [space(1, uuid: "u1"), space(2, uuid: "u2"), space(3, uuid: "u3")])
        let result = try XCTUnwrap(SpaceTracker.parseSpaces(displays: [d], focusedDisplayUUID: nil))
        XCTAssertEqual(result.spaces.map(\.id), ["u1", "u2", "u3"])
        XCTAssertEqual(result.spaces.map(\.index), [1, 2, 3])
        XCTAssertEqual(result.currentIndex, 2)
    }

    func testFullscreenSpacesAreExcludedFromIndexing() throws {
        // A fullscreen app (type 4) sits between two desktops.
        let d = display("A", current: 3, spaces: [space(1, uuid: "u1"), space(2, type: 4, uuid: "fs"), space(3, uuid: "u3")])
        let result = try XCTUnwrap(SpaceTracker.parseSpaces(displays: [d], focusedDisplayUUID: nil))
        XCTAssertEqual(result.spaces.map(\.id), ["u1", "u3"])
        XCTAssertEqual(result.currentIndex, 2)
    }

    func testCurrentFullscreenSpaceHasNoDesktopIndex() throws {
        let d = display("A", current: 2, spaces: [space(1, uuid: "u1"), space(2, type: 4, uuid: "fs")])
        let result = try XCTUnwrap(SpaceTracker.parseSpaces(displays: [d], focusedDisplayUUID: nil))
        XCTAssertNil(result.currentIndex)
        XCTAssertEqual(result.spaces.count, 1)
    }

    func testEmptyUUIDFallsBackToManagedSpaceID() {
        XCTAssertEqual(SpaceTracker.stableID(for: space(42, uuid: "")), "managed-42")
        XCTAssertEqual(SpaceTracker.stableID(for: space(7)), "managed-7")
        XCTAssertEqual(SpaceTracker.stableID(for: space(7, uuid: "abc")), "abc")
    }

    func testFocusedDisplayIsChosenCaseInsensitively() throws {
        let a = display("AAAA", current: 1, spaces: [space(1, uuid: "a1")])
        let b = display("BBBB", current: 2, spaces: [space(2, uuid: "b1"), space(3, uuid: "b2")])
        let result = try XCTUnwrap(SpaceTracker.parseSpaces(displays: [a, b], focusedDisplayUUID: "bbbb"))
        XCTAssertEqual(result.spaces.map(\.id), ["b1", "b2"])
    }

    func testFallsBackToMainDisplayThenFirst() throws {
        let a = display("AAAA", current: 1, spaces: [space(1, uuid: "a1")])
        let main = display("Main", current: 2, spaces: [space(2, uuid: "m1")])
        let viaMain = try XCTUnwrap(SpaceTracker.parseSpaces(displays: [a, main], focusedDisplayUUID: "unknown"))
        XCTAssertEqual(viaMain.spaces.map(\.id), ["m1"])
        let viaFirst = try XCTUnwrap(SpaceTracker.parseSpaces(displays: [a, a], focusedDisplayUUID: nil))
        XCTAssertEqual(viaFirst.spaces.map(\.id), ["a1"])
    }

    func testReturnsNilWhenThereAreNoDesktops() {
        let onlyFullscreen = display("A", current: 1, spaces: [space(1, type: 4)])
        XCTAssertNil(SpaceTracker.parseSpaces(displays: [onlyFullscreen], focusedDisplayUUID: nil))
        XCTAssertNil(SpaceTracker.parseSpaces(displays: [], focusedDisplayUUID: nil))
        XCTAssertNil(SpaceTracker.parseSpaces(displays: [["bogus": 1]], focusedDisplayUUID: nil))
    }
}
