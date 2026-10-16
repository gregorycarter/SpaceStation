import XCTest

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
        let result = try XCTUnwrap(SpaceSnapshot.parse(displays: [d], focusedDisplayUUID: nil)?.desktops)
        XCTAssertEqual(result.spaces.map(\.id), ["u1", "u2", "u3"])
        XCTAssertEqual(result.spaces.map(\.index), [1, 2, 3])
        XCTAssertEqual(result.currentIndex, 2)
    }

    func testFullscreenSpacesAreExcludedFromIndexing() throws {
        // A fullscreen app (type 4) sits between two desktops.
        let d = display("A", current: 3, spaces: [space(1, uuid: "u1"), space(2, type: 4, uuid: "fs"), space(3, uuid: "u3")])
        let result = try XCTUnwrap(SpaceSnapshot.parse(displays: [d], focusedDisplayUUID: nil)?.desktops)
        XCTAssertEqual(result.spaces.map(\.id), ["u1", "u3"])
        XCTAssertEqual(result.currentIndex, 2)
    }

    func testCurrentFullscreenSpaceHasNoDesktopIndex() throws {
        let d = display("A", current: 2, spaces: [space(1, uuid: "u1"), space(2, type: 4, uuid: "fs")])
        let result = try XCTUnwrap(SpaceSnapshot.parse(displays: [d], focusedDisplayUUID: nil)?.desktops)
        XCTAssertNil(result.currentIndex)
        XCTAssertEqual(result.spaces.count, 1)
    }

    func testEmptyUUIDFallsBackToManagedSpaceID() {
        XCTAssertEqual(SpaceSnapshot.stableID(for: space(42, uuid: "")), "managed-42")
        XCTAssertEqual(SpaceSnapshot.stableID(for: space(7)), "managed-7")
        XCTAssertEqual(SpaceSnapshot.stableID(for: space(7, uuid: "abc")), "abc")
    }

    func testFocusedDisplayIsChosenCaseInsensitively() throws {
        let a = display("AAAA", current: 1, spaces: [space(1, uuid: "a1")])
        let b = display("BBBB", current: 2, spaces: [space(2, uuid: "b1"), space(3, uuid: "b2")])
        let result = try XCTUnwrap(SpaceSnapshot.parse(displays: [a, b], focusedDisplayUUID: "bbbb")?.desktops)
        XCTAssertEqual(result.spaces.map(\.id), ["b1", "b2"])
    }

    func testFallsBackToMainDisplayThenFirst() throws {
        let a = display("AAAA", current: 1, spaces: [space(1, uuid: "a1")])
        let main = display("Main", current: 2, spaces: [space(2, uuid: "m1")])
        let viaMain = try XCTUnwrap(SpaceSnapshot.parse(displays: [a, main], focusedDisplayUUID: "unknown")?.desktops)
        XCTAssertEqual(viaMain.spaces.map(\.id), ["m1"])
        let viaFirst = try XCTUnwrap(SpaceSnapshot.parse(displays: [a, a], focusedDisplayUUID: nil)?.desktops)
        XCTAssertEqual(viaFirst.spaces.map(\.id), ["a1"])
    }

    func testReturnsNilWhenThereAreNoDesktops() {
        let onlyFullscreen = display("A", current: 1, spaces: [space(1, type: 4)])
        XCTAssertNil(SpaceSnapshot.parse(displays: [onlyFullscreen], focusedDisplayUUID: nil)?.desktops)
        XCTAssertNil(SpaceSnapshot.parse(displays: [], focusedDisplayUUID: nil)?.desktops)
        XCTAssertNil(SpaceSnapshot.parse(displays: [["bogus": 1]], focusedDisplayUUID: nil)?.desktops)
    }

    func testMissingManagedIDIsRetainedForNamingButExcludedFromStepping() throws {
        let d = display("A", current: 2, spaces: [
            ["type": 0, "uuid": "unmanaged"], space(2, uuid: "current"), ["type": 0]
        ])
        let snapshot = try XCTUnwrap(SpaceSnapshot.parse(displays: [d], focusedDisplayUUID: nil))
        XCTAssertEqual(snapshot.desktops?.spaces.map(\.id), ["unmanaged", "current", "managed-0"])
        XCTAssertEqual(snapshot.desktops?.currentIndex, 2)
        XCTAssertEqual(snapshot.order?.entries.map(\.managedID), [2])
        XCTAssertEqual(snapshot.order?.currentPosition, 0)
    }

    func testFullscreenOnlyDisplayStillHasASteppingOrder() throws {
        let d = display("A", current: 1, spaces: [space(1, type: 4)])
        let snapshot = try XCTUnwrap(SpaceSnapshot.parse(displays: [d], focusedDisplayUUID: nil))
        XCTAssertNil(snapshot.desktops)
        XCTAssertEqual(snapshot.order?.entries.count, 1)
        XCTAssertNil(snapshot.order?.entries.first?.desktopID)
    }

    func testMissingTypeDefaultsToDesktopAndDuplicateCurrentIDsUseFirstIndex() throws {
        let d = display("A", current: 1, spaces: [["ManagedSpaceID": 1], space(1, uuid: "duplicate")])
        let snapshot = try XCTUnwrap(SpaceSnapshot.parse(displays: [d], focusedDisplayUUID: nil))
        XCTAssertEqual(snapshot.desktops?.spaces.map(\.id), ["managed-1", "duplicate"])
        XCTAssertEqual(snapshot.desktops?.currentIndex, 1)
    }

    func testDesktopsCanExistWithoutASteppingOrder() throws {
        let d = display("A", current: 1, spaces: [["uuid": "unmanaged"]])
        let snapshot = try XCTUnwrap(SpaceSnapshot.parse(displays: [d], focusedDisplayUUID: nil))
        XCTAssertEqual(snapshot.desktops?.spaces.map(\.id), ["unmanaged"])
        XCTAssertNil(snapshot.desktops?.currentIndex)
        XCTAssertNil(snapshot.order)
    }
}
