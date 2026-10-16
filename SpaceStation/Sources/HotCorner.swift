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

/// Watches the pointer and calls `onTrigger` when it rests in the chosen corner.
///
/// Uses a global mouse-moved monitor, which needs no Accessibility or Input Monitoring
/// permission (only keyboard events do). It waits a short moment so flicking past the corner
/// doesn't fire, and re-arms only after the pointer has left the corner.
@MainActor
final class HotCornerMonitor {
    private let corner: HotCorner
    private let onTrigger: () -> Void
    private var monitor: Any?
    private var pending: DispatchWorkItem?
    private var armed = true

    private static let dwell: TimeInterval = 0.15
    /// Distance from the corner the pointer must move before the corner re-arms.
    private static let rearmDistance: CGFloat = 40

    init(corner: HotCorner, onTrigger: @escaping () -> Void) {
        self.corner = corner
        self.onTrigger = onTrigger
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in self?.pointerMoved() }
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private var screenFrames: [CGRect] { NSScreen.screens.map(\.frame) }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        if corner.contains(point, screens: screenFrames) {
            guard armed, pending == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pending = nil
                // Still resting in the corner after the dwell?
                if self.corner.contains(NSEvent.mouseLocation, screens: self.screenFrames) {
                    self.armed = false
                    self.onTrigger()
                }
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell, execute: work)
        } else {
            pending?.cancel()
            pending = nil
            if !armed, isFarFromCorner(point) { armed = true }
        }
    }

    private func isFarFromCorner(_ point: CGPoint) -> Bool {
        // Re-arm once the pointer is more than `rearmDistance` away from the corner on every screen.
        !screenFrames.contains { frame in
            let nearX = (corner == .topLeft || corner == .bottomLeft) ? frame.minX : frame.maxX
            let nearY = (corner == .topLeft || corner == .topRight) ? frame.maxY : frame.minY
            return frame.insetBy(dx: -1, dy: -1).contains(point)
                && abs(point.x - nearX) <= Self.rearmDistance && abs(point.y - nearY) <= Self.rearmDistance
        }
    }
}
