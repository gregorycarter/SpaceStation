import CoreGraphics
import Foundation
import os.log

/// Executes a stepping plan, polls for arrival, and makes at most two corrections.
/// System effects and time are injectable so tests never send keys or wait for animations.
@MainActor
final class SpaceSwitchExecutor {
    struct System {
        var post: @MainActor (KeyBinding) -> Void
        var now: @MainActor () -> Date
        var sleep: @MainActor (TimeInterval) async -> Void

        static let live = System(post: KeyEventPoster.post, now: Date.init, sleep: {
            try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        })
    }

    private(set) var isStepping = false
    private let system: System
    private let interval: TimeInterval
    private let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "SpaceSwitching")

    init(system: System? = nil, interval: TimeInterval? = nil) {
        self.system = system ?? .live
        self.interval = interval ?? Self.stepInterval
    }

    /// macOS queues transitions, so presses can be sent before each animation finishes.
    static var stepInterval: TimeInterval {
        #if DEBUG
        if let ms = ProcessInfo.processInfo.environment["SPACESTATION_DEBUG_STEP_INTERVAL_MS"].flatMap(Double.init) {
            return ms / 1000
        }
        #endif
        return 0.1
    }

    func post(_ binding: KeyBinding) { system.post(binding) }

    @discardableResult
    func start(to desktopID: String, firstPlan: SpaceStepper.Plan, moveLeft: KeyBinding, moveRight: KeyBinding,
               currentOrder: @escaping () -> SpaceOrder?, refresh: @escaping () -> Void) -> Task<Void, Never>? {
        guard !isStepping else { return nil }
        isStepping = true
        return Task { @MainActor in
            defer {
                isStepping = false
                refresh()   // Only now record the destination in desktop history.
            }
            var plan: SpaceStepper.Plan? = firstPlan
            for _ in 0..<3 {
                guard let current = plan else { return }
                let key = current.direction == .right ? moveRight : moveLeft
                for pressed in 0..<current.steps {
                    post(key)
                    if pressed < current.steps - 1 { await system.sleep(interval) }
                }
                guard await waitUntilSettled(on: desktopID, expectedSteps: current.steps,
                                            currentOrder: currentOrder, refresh: refresh) else {
                    logger.warning("Stepping stopped: the Space did not change")
                    return
                }
                refresh()
                guard let order = currentOrder() else { return }
                plan = SpaceStepper.plan(order: order, to: desktopID)
                if let plan { logger.info("Stepping: correcting by \(plan.steps)") }
            }
        }
    }

    private func waitUntilSettled(on desktopID: String, expectedSteps: Int,
                                  currentOrder: () -> SpaceOrder?, refresh: () -> Void) async -> Bool {
        let start = currentOrder()?.currentManagedID
        let deadline = system.now().addingTimeInterval(1.0 + 0.7 * Double(expectedSteps))
        var lastChange = system.now()
        var lastSeen = start
        var everMoved = false
        while system.now() < deadline {
            await system.sleep(0.04)
            refresh()
            let order = currentOrder()
            let now = order?.currentManagedID
            if now != lastSeen { lastSeen = now; lastChange = system.now(); everMoved = true }
            if let order, let to = order.position(ofDesktop: desktopID), order.currentPosition == to {
                return true
            }
            if everMoved, system.now().timeIntervalSince(lastChange) > 0.9 { return true }
        }
        return everMoved
    }
}

/// Sends the existing press/release sequence, including its nonblocking 20 ms delay.
@MainActor
private enum KeyEventPoster {
    static func post(_ binding: KeyBinding) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: binding.keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: binding.keyCode, keyDown: false) else {
            Logger(subsystem: "com.gregorycarter.SpaceStation", category: "SpaceSwitching")
                .error("Failed to create key events")
            return
        }
        keyDown.flags = binding.flags
        keyUp.flags = binding.flags
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { keyUp.post(tap: .cghidEventTap) }
    }
}
