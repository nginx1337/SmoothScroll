import Foundation

/// Scroll distance per wheel notch.
public enum SpeedPreset: String, CaseIterable, Sendable {
    case slow, normal, fast, veryFast

    public var pixelsPerNotch: Double {
        switch self {
        case .slow: 40
        case .normal: 60
        case .fast: 90
        case .veryFast: 130
        }
    }
}

/// Length of the glide after each notch.
public enum SmoothnessPreset: String, CaseIterable, Sendable {
    case low, medium, high

    public var smoothing: Double {
        switch self {
        case .low: 0.05
        case .medium: 0.09
        case .high: 0.15
        }
    }
}
