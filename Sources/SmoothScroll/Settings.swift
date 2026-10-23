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
        static let minNotchMs = 40.0
    }

    /// Slider limits shared by the settings window and the menu.
    enum Range {
        static let pixelsPerNotch: ClosedRange<Double> = 20...200
        static let smoothingMs: ClosedRange<Double> = 30...300
        static let step: Double = 5
        static let minNotchMs: ClosedRange<Double> = 10...150
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
    /// Drop wheel notches that arrive faster than `minNotchMs` (free-spinning wheels).
    var limitRate: Bool { didSet { save(limitRate, Key.limitRate) } }
    var minNotchMs: Double { didSet { save(minNotchMs, Key.minNotchMs) } }
    /// Per-application overrides and exclusions.
    var profiles: [AppProfile] { didSet { saveProfiles() } }
    /// Stop the glide when the pointer leaves the window being scrolled.
    var stopOnWindowChange: Bool { didSet { save(stopOnWindowChange, Key.stopOnWindowChange) } }

    /// Runtime state shown in the UI, not persisted.
    var accessGranted = false
    var launchAtLogin = false
    var loginError: String?
    /// Foreground app other than SmoothScroll itself; picks the active profile.
    var frontmostBundleID: String?
    var frontmostName: String?
    /// Profile expanded in the settings window.
    var selectedProfileID: String?

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
            Key.limitRate: false,
            Key.minNotchMs: Default.minNotchMs,
            Key.stopOnWindowChange: true,
        ])
        Self.migrateLegacyPresets(defaults)
        enabled = defaults.bool(forKey: Key.enabled)
        pixelsPerNotch = defaults.double(forKey: Key.pixelsPerNotch)
        smoothingMs = defaults.double(forKey: Key.smoothingMs)
        accelerate = defaults.bool(forKey: Key.accelerate)
        acceleration = defaults.double(forKey: Key.acceleration)
        reverse = defaults.bool(forKey: Key.reverse)
        limitRate = defaults.bool(forKey: Key.limitRate)
        minNotchMs = defaults.double(forKey: Key.minNotchMs)
        profiles = defaults.data(forKey: Key.profiles)
            .flatMap { try? JSONDecoder().decode([AppProfile].self, from: $0) } ?? []
        stopOnWindowChange = defaults.bool(forKey: Key.stopOnWindowChange)
    }

    var scrollConfig: ScrollConfig {
        ScrollConfig(
            pixelsPerNotch: pixelsPerNotch,
            smoothing: smoothingMs / 1000,
            acceleration: accelerate ? acceleration : 0,
            reverse: reverse,
            minNotchInterval: limitRate ? minNotchMs / 1000 : 0
        )
    }

    // MARK: - Per-app profiles

    func profile(for bundleID: String?) -> AppProfile? {
        guard let bundleID else { return nil }
        return profiles.first { $0.bundleID == bundleID }
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        profile(for: bundleID)?.excluded ?? false
    }

    /// Parameters for the given foreground app: its profile, else the global ones.
    func scrollConfig(for bundleID: String?) -> ScrollConfig {
        guard let profile = profile(for: bundleID), !profile.excluded else { return scrollConfig }
        return profile.scrollConfig
    }

    /// Returns the app's profile, creating one that starts as a copy of the global settings.
    @discardableResult
    func ensureProfile(bundleID: String, name: String) -> AppProfile {
        if let existing = profile(for: bundleID) { return existing }
        let created = AppProfile(
            bundleID: bundleID, name: name,
            pixelsPerNotch: pixelsPerNotch, smoothingMs: smoothingMs,
            accelerate: accelerate, acceleration: acceleration, reverse: reverse,
            limitRate: limitRate, minNotchMs: minNotchMs
        )
        profiles.append(created)
        return created
    }

    func setExcluded(_ excluded: Bool, bundleID: String, name: String) {
        ensureProfile(bundleID: bundleID, name: name)
        if let index = profiles.firstIndex(where: { $0.bundleID == bundleID }) {
            profiles[index].excluded = excluded
        }
    }

    /// Adds a profile for the app bundle at `url`; returns its id, or nil if it has no bundle ID.
    @discardableResult
    func addProfile(appURL url: URL) -> String? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        ensureProfile(bundleID: id, name: name)
        return id
    }

    func removeProfile(_ id: String) {
        profiles.removeAll { $0.id == id }
        if selectedProfileID == id { selectedProfileID = nil }
    }

    func resetToDefaults() {
        pixelsPerNotch = Default.pixelsPerNotch
        smoothingMs = Default.smoothingMs
        accelerate = true
        acceleration = Default.acceleration
        reverse = false
        limitRate = false
        minNotchMs = Default.minNotchMs
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

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: Key.profiles) }
        onChange()
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
        static let limitRate = "limitRate"
        static let minNotchMs = "minNotchMs"
        static let profiles = "appProfiles"
        static let stopOnWindowChange = "stopOnWindowChange"
        static let legacySpeed = "speed"
        static let legacySmoothness = "smoothness"
    }
}
