import Foundation

/// The parts of a scroll-wheel event the filter needs, extracted from a
/// `CGEvent` by the app so the decision itself stays pure and testable.
public struct WheelEventInfo: Equatable, Sendable {
    /// Event carries our own marker (posted by the animator).
    public var isSynthetic: Bool
    /// Trackpad, Magic Mouse or another already-smooth device.
    public var isContinuous: Bool
    /// ⌘, ⌃ or ⌥ held (zoom and similar gestures).
    public var hasGestureModifier: Bool
    /// `kCGScrollWheelEventDeltaAxis1` (vertical, lines).
    public var deltaVertical: Int64
    /// `kCGScrollWheelEventDeltaAxis2` (horizontal, lines).
    public var deltaHorizontal: Int64

    public init(isSynthetic: Bool, isContinuous: Bool, hasGestureModifier: Bool,
                deltaVertical: Int64, deltaHorizontal: Int64) {
        self.isSynthetic = isSynthetic
        self.isContinuous = isContinuous
        self.hasGestureModifier = hasGestureModifier
        self.deltaVertical = deltaVertical
        self.deltaHorizontal = deltaHorizontal
    }
}

public enum WheelDecision: Equatable, Sendable {
    /// Deliver the event untouched.
    case passThrough
    /// Swallow the event and animate this many notches instead.
    case smooth(vertical: Double, horizontal: Double)
}

public enum ScrollEventFilter {
    /// Upper bound on notches taken from a single event. The system coalesces
    /// several notches into one event under load and also accelerates line
    /// deltas on fast spins; the cap keeps the magnitude while preventing the
    /// system's acceleration from stacking on top of the animator's.
    public static let maxNotchesPerEvent: Int64 = 4

    public static func decide(_ event: WheelEventInfo, enabled: Bool) -> WheelDecision {
        guard enabled,
              !event.isSynthetic,
              !event.isContinuous,
              !event.hasGestureModifier,
              event.deltaVertical != 0 || event.deltaHorizontal != 0
        else { return .passThrough }
        return .smooth(vertical: notches(event.deltaVertical), horizontal: notches(event.deltaHorizontal))
    }

    private static func notches(_ delta: Int64) -> Double {
        Double(min(max(delta, -maxNotchesPerEvent), maxNotchesPerEvent))
    }
}
