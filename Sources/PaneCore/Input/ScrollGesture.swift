import CoreGraphics

/// Turns Mac scrolling into a one-finger drag on the device's screen.
///
/// The emulator's `WheelEvent` only reaches AVDs with a mouse wheel device, and phone AVDs
/// have touch only, so Pane scrolls by touch: a trackpad's began, changed and ended phases put
/// a finger down at the pointer, move it with the content and lift it (Android flings from the
/// release, so momentum events are ignored). A mouse wheel has no phases: each notch moves the
/// finger, and the caller lifts it after a short idle (`endWheel`).
///
/// Points are in the screen's view coordinates (y down). The Mac's deltas already say which way
/// the content should move, and the finger moves with the content.
public struct ScrollGesture: Sendable, Equatable {
    public enum Phase: Sendable {
        case began
        case changed
        case ended
        /// A mouse wheel notch or line, without phases.
        case wheel
    }

    public enum Action: Sendable, Equatable {
        case down(CGPoint)
        case move(CGPoint)
        case up(CGPoint)
    }

    public private(set) var finger: CGPoint?

    public init() {}

    /// Handles one scroll event. `bounds` is the screen; a finger that would leave it lifts at
    /// the edge, and the next event starts a new drag from the pointer.
    public mutating func handle(phase: Phase, pointer: CGPoint, delta: CGVector, bounds: CGRect) -> [Action] {
        var actions: [Action] = []
        switch phase {
        case .began, .changed, .wheel:
            if finger == nil {
                guard bounds.contains(pointer) else { return [] }
                finger = pointer
                actions.append(.down(pointer))
            }
            guard let current = finger, delta.dx != 0 || delta.dy != 0 else { return actions }
            let next = CGPoint(x: current.x + delta.dx, y: current.y + delta.dy)
            if bounds.contains(next) {
                finger = next
                actions.append(.move(next))
            } else {
                let edge = CGPoint(
                    x: min(max(next.x, bounds.minX), bounds.maxX - 1), y: min(max(next.y, bounds.minY), bounds.maxY - 1)
                )
                finger = nil
                actions.append(.move(edge))
                actions.append(.up(edge))
            }
        case .ended:
            if let current = finger {
                finger = nil
                actions.append(.up(current))
            }
        }
        return actions
    }

    /// Lifts a wheel's finger once the wheel has been still for a moment.
    public mutating func endWheel() -> Action? {
        guard let current = finger else { return nil }
        finger = nil
        return .up(current)
    }
}
