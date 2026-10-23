import Foundation

/// Per-application override: either turns smooth scrolling off for the app
/// or replaces the global scroll parameters while it is in the foreground.
public struct AppProfile: Codable, Equatable, Identifiable, Sendable {
    public var bundleID: String
    public var name: String
    /// Leave this app's wheel events completely untouched.
    public var excluded: Bool
    public var pixelsPerNotch: Double
    public var smoothingMs: Double
    public var accelerate: Bool
    public var acceleration: Double
    public var reverse: Bool
    public var limitRate: Bool
    public var minNotchMs: Double

    public var id: String { bundleID }

    public init(
        bundleID: String,
        name: String,
        excluded: Bool = false,
        pixelsPerNotch: Double = SpeedPreset.normal.pixelsPerNotch,
        smoothingMs: Double = SmoothnessPreset.medium.smoothing * 1000,
        accelerate: Bool = true,
        acceleration: Double = ScrollConfig().acceleration,
        reverse: Bool = false,
        limitRate: Bool = false,
        minNotchMs: Double = 40
    ) {
        self.bundleID = bundleID
        self.name = name
        self.excluded = excluded
        self.pixelsPerNotch = pixelsPerNotch
        self.smoothingMs = smoothingMs
        self.accelerate = accelerate
        self.acceleration = acceleration
        self.reverse = reverse
        self.limitRate = limitRate
        self.minNotchMs = minNotchMs
    }

    public var scrollConfig: ScrollConfig {
        ScrollConfig(
            pixelsPerNotch: pixelsPerNotch,
            smoothing: smoothingMs / 1000,
            acceleration: accelerate ? acceleration : 0,
            reverse: reverse,
            minNotchInterval: limitRate ? minNotchMs / 1000 : 0
        )
    }
}
