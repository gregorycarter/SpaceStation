import AppKit
import os.log

/// A screen corner that can open the Space switcher when the pointer is pushed into it.
enum HotCorner: String, CaseIterable, Identifiable {
    case off, topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }

    /// How close (in points) to the corner the pointer must be.
    static let threshold: CGFloat = 3

    /// Whether `point` (global coordinates, origin bottom-left, as `NSEvent.mouseLocation`)
    /// is in this corner of one of the `screens`.
    ///
    /// A corner that touches another display (e.g. the top-right of the left monitor when a
    /// second monitor sits to its right) is ignored, because the pointer is just crossing
    /// between displays there.
    func contains(_ point: CGPoint, screens: [CGRect]) -> Bool {
        guard self != .off else { return false }
        for screen in screens where screen.insetBy(dx: -1, dy: -1).contains(point) {
            let corner = cornerPoint(of: screen)
            guard abs(point.x - corner.x) <= Self.threshold,
                  abs(point.y - corner.y) <= Self.threshold else { continue }

            // Probe just outside the corner, horizontally and vertically.
            let (sx, sy) = outwardDirection
            let horizontalProbe = CGPoint(x: corner.x + sx * 4, y: corner.y - sy * 4)
            let verticalProbe = CGPoint(x: corner.x - sx * 4, y: corner.y + sy * 4)
            let touchesAnotherDisplay = screens.contains { other in
                other != screen && (other.contains(horizontalProbe) || other.contains(verticalProbe))
            }
            if !touchesAnotherDisplay { return true }
        }
        return false
    }

    private func cornerPoint(of frame: CGRect) -> CGPoint {
        switch self {
        case .off: return .zero
        case .topLeft: return CGPoint(x: frame.minX, y: frame.maxY)
        case .topRight: return CGPoint(x: frame.maxX, y: frame.maxY)
        case .bottomLeft: return CGPoint(x: frame.minX, y: frame.minY)
        case .bottomRight: return CGPoint(x: frame.maxX, y: frame.minY)
        }
    }

    /// +1 / -1 for which way is "outside" the screen, horizontally (sx) and vertically (sy).
    private var outwardDirection: (CGFloat, CGFloat) {
        switch self {
        case .off: return (0, 0)
        case .topLeft: return (-1, 1)
        case .topRight: return (1, 1)
        case .bottomLeft: return (-1, -1)
        case .bottomRight: return (1, -1)
        }
    }
}

extension HotCorner {
    /// Whether `point` is within `distance` points of this corner on any screen.
    func isNear(_ point: CGPoint, distance: CGFloat, screens: [CGRect]) -> Bool {
        guard self != .off else { return false }
        return screens.contains { frame in
            guard frame.insetBy(dx: -1, dy: -1).contains(point) else { return false }
            let corner = cornerPointForProximity(of: frame)
            return abs(point.x - corner.x) <= distance && abs(point.y - corner.y) <= distance
        }
    }

    private func cornerPointForProximity(of frame: CGRect) -> CGPoint {
        switch self {
        case .off, .topLeft: return CGPoint(x: frame.minX, y: frame.maxY)
        case .topRight: return CGPoint(x: frame.maxX, y: frame.maxY)
        case .bottomLeft: return CGPoint(x: frame.minX, y: frame.minY)
        case .bottomRight: return CGPoint(x: frame.maxX, y: frame.minY)
        }
    }
}

/// Decides when resting the pointer in a corner should trigger: the pointer must stay in the
/// corner for `dwell` seconds, and after firing the corner re-arms only once the pointer has
/// moved `rearmDistance` away. Pure state machine, fed samples, so it is easy to test.
struct HotCornerTrigger {
    let corner: HotCorner
    var dwell: TimeInterval
    var rearmDistance: CGFloat

    /// Short enough to feel immediate, but long enough (two consecutive samples; this is deliberately a little under the 20 ms poll interval so the second sample always qualifies) that the pointer must
    /// actually arrive in the corner rather than graze a single pixel on the way past.
    static let defaultDwell: TimeInterval = 0.015

    private var enteredAt: TimeInterval?
    private var armed = true

    init(corner: HotCorner, dwell: TimeInterval = HotCornerTrigger.defaultDwell, rearmDistance: CGFloat = 40) {
        self.corner = corner
        self.dwell = dwell
        self.rearmDistance = rearmDistance
    }

    /// Feed the current pointer position; returns true when the corner should fire.
    mutating func sample(point: CGPoint, screens: [CGRect], at time: TimeInterval) -> Bool {
        if corner.contains(point, screens: screens) {
            guard armed else { return false }
            let entered = enteredAt ?? time
            enteredAt = entered
            if time - entered >= dwell {
                armed = false
                enteredAt = nil
                return true
            }
            return false
        }

        enteredAt = nil
        if !armed, !corner.isNear(point, distance: rearmDistance, screens: screens) {
            armed = true
        }
        return false
    }
}

/// Polls the pointer position and calls `onTrigger` when it rests in the chosen corner.
///
/// Sampling `NSEvent.mouseLocation` needs no permission at all and works whether or not
/// mouse-moved events are delivered (a global event monitor can miss them, and a pointer pinned
/// in a corner generates none at rest). It runs only while a corner is selected.
@MainActor
final class HotCornerMonitor {
    private var trigger: HotCornerTrigger
    private let onTrigger: () -> Void
    private var timer: Timer?

    private static let interval: TimeInterval = 0.02

    init(corner: HotCorner, onTrigger: @escaping () -> Void) {
        self.trigger = HotCornerTrigger(corner: corner)
        self.onTrigger = onTrigger
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    private func tick() {
        let fired = trigger.sample(point: NSEvent.mouseLocation,
                                   screens: NSScreen.screens.map(\.frame),
                                   at: ProcessInfo.processInfo.systemUptime)
        if fired { onTrigger() }
    }
}
