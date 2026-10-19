import Foundation
import Observation
import SmoothScrollCore

/// User preferences persisted in UserDefaults (~/Library/Preferences).
/// Observable so the settings window updates live; `onChange` pushes every
/// edit to the scroll interceptor immediately.
@MainActor
@Observable
final class Settings {
    enum Default {
        static let pixelsPerNotch = SpeedPreset.normal.pixelsPerNotch
        static let smoothingMs = SmoothnessPreset.medium.smoothing * 1000
        static let acceleration = ScrollConfig().acceleration
    }

    var enabled: Bool { didSet { save(enabled, Key.enabled) } }
    /// Pixels per wheel notch.
    var pixelsPerNotch: Double { didSet { save(pixelsPerNotch, Key.pixelsPerNotch) } }
    /// Glide time constant in milliseconds.
    var smoothingMs: Double { didSet { save(smoothingMs, Key.smoothingMs) } }
    var accelerate: Bool { didSet { save(accelerate, Key.accelerate) } }
    /// Extra multiplier per consecutive fast notch.
    var acceleration: Double { didSet { save(acceleration, Key.acceleration) } }
    var reverse: Bool { didSet { save(reverse, Key.reverse) } }
    /// Stop the glide when the pointer leaves the window being scrolled.
    var stopOnWindowChange: Bool { didSet { save(stopOnWindowChange, Key.stopOnWindowChange) } }

    /// Runtime state shown in the UI, not persisted.
    var accessGranted = false
    var launchAtLogin = false
    var loginError: String?

    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.pixelsPerNotch: Default.pixelsPerNotch,
            Key.smoothingMs: Default.smoothingMs,
            Key.accelerate: true,
            Key.acceleration: Default.acceleration,
            Key.reverse: false,
            Key.stopOnWindowChange: true,
        ])
        Self.migrateLegacyPresets(defaults)
        enabled = defaults.bool(forKey: Key.enabled)
        pixelsPerNotch = defaults.double(forKey: Key.pixelsPerNotch)
        smoothingMs = defaults.double(forKey: Key.smoothingMs)
        accelerate = defaults.bool(forKey: Key.accelerate)
        acceleration = defaults.double(forKey: Key.acceleration)
        reverse = defaults.bool(forKey: Key.reverse)
        stopOnWindowChange = defaults.bool(forKey: Key.stopOnWindowChange)
    }

    var scrollConfig: ScrollConfig {
        ScrollConfig(
            pixelsPerNotch: pixelsPerNotch,
            smoothing: smoothingMs / 1000,
            acceleration: accelerate ? acceleration : 0,
            reverse: reverse
        )
    }

    func resetToDefaults() {
        pixelsPerNotch = Default.pixelsPerNotch
        smoothingMs = Default.smoothingMs
        accelerate = true
        acceleration = Default.acceleration
        reverse = false
        stopOnWindowChange = true
    }

    /// Version 1.0 stored preset names; convert them to the numeric values.
    private static func migrateLegacyPresets(_ defaults: UserDefaults) {
        if let raw = defaults.string(forKey: Key.legacySpeed) {
            if let preset = SpeedPreset(rawValue: raw) {
                defaults.set(preset.pixelsPerNotch, forKey: Key.pixelsPerNotch)
            }
            defaults.removeObject(forKey: Key.legacySpeed)
        }
        if let raw = defaults.string(forKey: Key.legacySmoothness) {
            if let preset = SmoothnessPreset(rawValue: raw) {
                defaults.set(preset.smoothing * 1000, forKey: Key.smoothingMs)
            }
            defaults.removeObject(forKey: Key.legacySmoothness)
        }
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange()
    }

    private enum Key {
        static let enabled = "enabled"
        static let pixelsPerNotch = "pixelsPerNotch"
        static let smoothingMs = "smoothingMs"
        static let accelerate = "accelerate"
        static let acceleration = "acceleration"
        static let reverse = "reverse"
        static let stopOnWindowChange = "stopOnWindowChange"
        static let legacySpeed = "speed"
        static let legacySmoothness = "smoothness"
    }
}
