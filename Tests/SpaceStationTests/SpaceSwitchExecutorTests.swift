import XCTest

@MainActor
final class SpaceSwitchExecutorTests: XCTestCase {
    @MainActor
    private final class Simulation {
        var clock = Date(timeIntervalSince1970: 0)
        var sleeps: [TimeInterval] = []
        var keys: [KeyBinding] = []
        var currentID = 1
        var hasOrder = true
        var onRefresh: (Simulation) -> Void = { _ in }
        var history = SpaceHistory()
        var steppingDuringRefresh: [Bool] = []
        let left = KeyBinding(keyCode: 123, flags: .maskControl)
        let right = KeyBinding(keyCode: 124, flags: .maskControl)

        lazy var executor = SpaceSwitchExecutor(system: .init(
            post: { [unowned self] in keys.append($0) },
            now: { [unowned self] in clock },
            sleep: { [unowned self] interval in
                sleeps.append(interval)
                clock = clock.addingTimeInterval(interval)
            }), interval: 0.1)

        init() { history.record(currentDesktopID: "A") }

        var order: SpaceOrder? {
            guard hasOrder else { return nil }
            return SpaceOrder(entries: [
                .init(managedID: 1, desktopID: "A"), .init(managedID: 2, desktopID: "B"),
                .init(managedID: 3, desktopID: nil), .init(managedID: 4, desktopID: "C"),
                .init(managedID: 5, desktopID: "D")
            ], currentManagedID: currentID)
        }

        func start(to id: String) -> Task<Void, Never>? {
            guard let order, let plan = SpaceStepper.plan(order: order, to: id) else { return nil }
            return executor.start(to: id, firstPlan: plan, moveLeft: left, moveRight: right,
                                  currentOrder: { [self] in self.order }, refresh: { [self] in
                onRefresh(self)
                steppingDuringRefresh.append(executor.isStepping)
                if !executor.isStepping {
                    history.record(currentDesktopID: self.order?.entries.first { $0.managedID == currentID }?.desktopID)
                }
            })
        }
    }

    func testArrivalPreservesPressIntervalsAndRecordsOnlyTheDestination() async throws {
        let s = Simulation()
        var positions = [2, 3, 4] // Pass through a desktop and fullscreen before reaching C.
        s.onRefresh = { if !positions.isEmpty { $0.currentID = positions.removeFirst() } }
        let task = try XCTUnwrap(s.start(to: "C"))
        XCTAssertTrue(s.executor.isStepping, "history must be suppressed before the task starts")
        await task.value
        XCTAssertEqual(s.keys, [s.right, s.right, s.right])
        XCTAssertEqual(Array(s.sleeps.prefix(2)), [0.1, 0.1])
        XCTAssertTrue(s.sleeps.dropFirst(2).allSatisfy { $0 == 0.04 })
        XCTAssertEqual(s.history.previousID, "A")
        XCTAssertFalse(s.executor.isStepping)
        XCTAssertEqual(s.steppingDuringRefresh.last, false)
        XCTAssertTrue(s.steppingDuringRefresh.dropLast().allSatisfy { $0 })
    }

    func testOvershootIsCorrectedInTheOppositeDirection() async throws {
        let s = Simulation()
        s.onRefresh = { $0.currentID = $0.keys.count < 3 ? 4 : 2 }
        await (try XCTUnwrap(s.start(to: "B"))).value
        XCTAssertEqual(s.keys, [s.right, s.left, s.left])
        XCTAssertEqual(s.currentID, 2)
    }

    func testNoMovementStopsWithoutCorrection() async throws {
        let s = Simulation()
        await (try XCTUnwrap(s.start(to: "B"))).value
        XCTAssertEqual(s.keys, [s.right])
        XCTAssertGreaterThanOrEqual(s.clock.timeIntervalSince1970, 1.7)
        XCTAssertFalse(s.executor.isStepping)
        XCTAssertNil(s.history.previousID)
    }

    func testGivesUpAfterTwoCorrections() async throws {
        let s = Simulation()
        s.onRefresh = { $0.currentID = $0.keys.count == 7 ? 3 : 2 }
        await (try XCTUnwrap(s.start(to: "D"))).value
        XCTAssertEqual(s.keys.count, 9, "4 initial presses, then corrections of 3 and 2")
        XCTAssertNotEqual(s.currentID, 5)
        XCTAssertFalse(s.executor.isStepping)
    }

    func testSecondSteppingRequestDoesNotStartAnotherSequence() async throws {
        let s = Simulation()
        s.onRefresh = { $0.currentID = 2 }
        let task = try XCTUnwrap(s.start(to: "B"))
        XCTAssertNil(s.start(to: "C"))
        await task.value
        XCTAssertEqual(s.keys, [s.right])
    }

    func testLosingTheOrderStillFinishesAndRestoresHistoryRecording() async throws {
        let s = Simulation()
        s.onRefresh = { $0.hasOrder = false }
        await (try XCTUnwrap(s.start(to: "B"))).value
        XCTAssertEqual(s.keys, [s.right])
        XCTAssertFalse(s.executor.isStepping)
        XCTAssertEqual(s.steppingDuringRefresh.last, false)
    }
}
