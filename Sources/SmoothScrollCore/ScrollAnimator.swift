import Foundation

/// Tunable parameters of the smooth-scroll animation.
public struct ScrollConfig: Equatable, Sendable {
    /// Pixels scrolled per wheel notch before acceleration.
    public var pixelsPerNotch: Double
    /// Time constant of the exponential ease-out, in seconds.
    /// Larger = longer, softer glide.
    public var smoothing: Double
    /// Extra multiplier added per consecutive fast notch (0 disables acceleration).
    public var acceleration: Double
    /// Upper bound for the acceleration multiplier.
    public var maxMultiplier: Double
    /// Notches closer than this (seconds) count as a continuous fast spin.
    public var accelerationWindow: Double
    /// Invert scroll direction for the mouse wheel only.
    public var reverse: Bool
    /// Notches in the same direction arriving closer than this (seconds) are
    /// dropped. Tames free-spinning wheels that fire dozens of events per
    /// second (0 disables the limit).
    public var minNotchInterval: Double

    public init(
        pixelsPerNotch: Double = 60,
        smoothing: Double = 0.09,
        acceleration: Double = 0.35,
        maxMultiplier: Double = 4,
        accelerationWindow: Double = 0.09,
        reverse: Bool = false,
        minNotchInterval: Double = 0
    ) {
        self.pixelsPerNotch = pixelsPerNotch
        self.smoothing = smoothing
        self.acceleration = acceleration
        self.maxMultiplier = maxMultiplier
        self.accelerationWindow = accelerationWindow
        self.reverse = reverse
        self.minNotchInterval = minNotchInterval
    }

    /// Clamps every value into a safe range so bad defaults can never
    /// produce runaway or frozen scrolling.
    public func sanitized() -> ScrollConfig {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
            v.isFinite ? min(max(v, lo), hi) : lo
        }
        var c = self
        c.pixelsPerNotch = clamp(pixelsPerNotch, 5, 400)
        c.smoothing = clamp(smoothing, 0.02, 0.5)
        c.acceleration = clamp(acceleration, 0, 2)
        c.maxMultiplier = clamp(maxMultiplier, 1, 10)
        c.accelerationWindow = clamp(accelerationWindow, 0.01, 0.5)
        c.minNotchInterval = clamp(minNotchInterval, 0, 0.5)
        return c
    }
}

/// One frame of output: whole pixels to post on each axis.
public struct ScrollStep: Equatable, Sendable {
    public var vertical: Int32
    public var horizontal: Int32
    public static let zero = ScrollStep(vertical: 0, horizontal: 0)
    public var isZero: Bool { vertical == 0 && horizontal == 0 }
}

/// Converts discrete wheel notches into a stream of small pixel deltas
/// that follow an exponential ease-out curve.
///
/// The animator is a pure value type: feed it notches with `addNotches`,
/// call `step(dt:)` once per display frame, post the returned pixels.
/// Sub-pixel remainders are carried between frames, so a finished glide
/// emits the requested distance rounded to the nearest whole pixel.
public struct ScrollAnimator: Sendable {
    public var config: ScrollConfig {
        didSet { config = config.sanitized() }
    }

    private var vertical = Axis()
    private var horizontal = Axis()

    public init(config: ScrollConfig = ScrollConfig()) {
        self.config = config.sanitized()
    }

    /// True when nothing is left to emit; the frame driver may stop.
    public var isIdle: Bool { vertical.isIdle && horizontal.isIdle }

    /// Distance (pixels) still to be emitted, for diagnostics and tests.
    public var pending: (vertical: Double, horizontal: Double) {
        (vertical.remaining, horizontal.remaining)
    }

    /// Registers wheel notches. Positive vertical = content moves down
    /// (same sign convention as `kCGScrollWheelEventDeltaAxis1`).
    public mutating func addNotches(vertical dv: Double, horizontal dh: Double, at time: TimeInterval) {
        let sign: Double = config.reverse ? -1 : 1
        if dv != 0 { vertical.add(notches: dv * sign, at: time, config: config) }
        if dh != 0 { horizontal.add(notches: dh * sign, at: time, config: config) }
    }

    /// Advances the animation by `dt` seconds and returns whole pixels to post.
    public mutating func step(dt: TimeInterval) -> ScrollStep {
        // Guard against stalls (sleep, debugger): never jump more than 1/15 s.
        let dt = dt.isFinite ? min(max(dt, 0), 1.0 / 15.0) : 0
        let fraction = 1 - exp(-dt / config.smoothing)
        return ScrollStep(
            vertical: vertical.advance(fraction: fraction),
            horizontal: horizontal.advance(fraction: fraction)
        )
    }

    /// Drops any in-flight motion (e.g. when the feature is turned off).
    public mutating func reset() {
        vertical = Axis()
        horizontal = Axis()
    }
}

private struct Axis: Sendable {
    /// Pixels requested but not yet emitted (fractional).
    var remaining: Double = 0
    /// Fractional pixels already "spent" by the curve but not yet posted.
    var carry: Double = 0
    var lastNotchTime: TimeInterval = -.infinity
    var lastDirection: Double = 0
    var streak: Int = 0

    /// Below this, the tail is flushed in one go so the glide ends crisply.
    static let snapThreshold = 1.0

    var isIdle: Bool { remaining == 0 && carry == 0 }

    mutating func add(notches: Double, at time: TimeInterval, config: ScrollConfig) {
        guard notches.isFinite, notches != 0 else { return }
        let direction: Double = notches > 0 ? 1 : -1

        // Free-spinning wheel: keep only one notch per interval.
        if config.minNotchInterval > 0, direction == lastDirection,
           time - lastNotchTime < config.minNotchInterval { return }

        if direction != lastDirection {
            // Direction reversal: stop the old glide immediately.
            remaining = 0
            carry = 0
            streak = 0
        } else if time - lastNotchTime <= config.accelerationWindow {
            streak += 1
        } else {
            streak = 0
        }
        lastDirection = direction
        lastNotchTime = time

        let multiplier = min(1 + config.acceleration * Double(streak), config.maxMultiplier)
        remaining += notches * config.pixelsPerNotch * multiplier

        // Hard cap so a stuck/fast wheel can never queue an absurd distance.
        let cap = config.pixelsPerNotch * config.maxMultiplier * 20
        remaining = min(max(remaining, -cap), cap)
    }

    mutating func advance(fraction: Double) -> Int32 {
        guard !isIdle else { return 0 }
        var move = remaining * fraction
        if abs(remaining - move) < Self.snapThreshold { move = remaining }
        remaining -= move
        carry += move
        // On the last frame round to nearest so the glide's total matches
        // the requested distance; mid-glide truncate and carry the rest.
        let whole = remaining == 0 ? carry.rounded() : carry.rounded(.towardZero)
        carry = remaining == 0 ? 0 : carry - whole
        return Int32(clamping: Int(whole))
    }
}
