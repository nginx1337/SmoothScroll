import Foundation
import Testing
@testable import SmoothScrollCore

/// Runs the animator at `fps` until idle; returns per-frame vertical pixels.
private func drain(_ animator: inout ScrollAnimator, fps: Double = 120, maxFrames: Int = 10_000) -> [Int32] {
    var frames: [Int32] = []
    while !animator.isIdle && frames.count < maxFrames {
        frames.append(animator.step(dt: 1 / fps).vertical)
    }
    return frames
}

private let noAccel = ScrollConfig(pixelsPerNotch: 60, smoothing: 0.09, acceleration: 0)

@Suite struct ScrollAnimatorTests {
    @Test func startsIdle() {
        var a = ScrollAnimator()
        #expect(a.isIdle)
        #expect(a.step(dt: 1 / 60) == .zero)
    }

    @Test func singleNotchEmitsExactDistance() {
        var a = ScrollAnimator(config: noAccel)
        a.addNotches(vertical: 1, horizontal: 0, at: 0)
        let frames = drain(&a)
        #expect(frames.reduce(0, +) == 60)
        #expect(a.isIdle)
    }

    @Test(arguments: [30.0, 60, 120, 144, 240])
    func distanceIndependentOfFrameRate(fps: Double) {
        var a = ScrollAnimator(config: noAccel)
        a.addNotches(vertical: -1, horizontal: 0, at: 0)
        #expect(drain(&a, fps: fps).reduce(0, +) == -60)
    }

    @Test func glideIsEaseOut() {
        var a = ScrollAnimator(config: noAccel)
        a.addNotches(vertical: 1, horizontal: 0, at: 0)
        let frames = drain(&a).map { Int($0) }
        #expect(frames.count > 5, "should be spread over several frames")
        #expect(frames.allSatisfy { $0 >= 0 }, "never moves backwards")
        // Fast start, slow tail.
        #expect(frames.first! > frames[frames.count / 2])
    }

    @Test func glideFinishesInReasonableTime() {
        var a = ScrollAnimator(config: ScrollConfig(smoothing: 0.15, acceleration: 0))
        a.addNotches(vertical: 1, horizontal: 0, at: 0)
        let frames = drain(&a, fps: 60)
        #expect(Double(frames.count) / 60 < 1.5)
    }

    @Test func horizontalAxisIsIndependent() {
        var a = ScrollAnimator(config: noAccel)
        a.addNotches(vertical: 0, horizontal: 1, at: 0)
        var total: Int32 = 0
        while !a.isIdle {
            let s = a.step(dt: 1 / 120)
            #expect(s.vertical == 0)
            total += s.horizontal
        }
        #expect(total == 60)
    }

    @Test func reverseFlipsDirection() {
        var cfg = noAccel
        cfg.reverse = true
        var a = ScrollAnimator(config: cfg)
        a.addNotches(vertical: 1, horizontal: 0, at: 0)
        #expect(drain(&a).reduce(0, +) == -60)
    }

    @Test func directionChangeCancelsPreviousGlide() {
        var a = ScrollAnimator(config: noAccel)
        a.addNotches(vertical: 1, horizontal: 0, at: 0)
        _ = a.step(dt: 1 / 120)
        a.addNotches(vertical: -1, horizontal: 0, at: 0.01)
        #expect(a.pending.vertical == -60)
        let rest = drain(&a)
        #expect(rest.allSatisfy { $0 <= 0 }, "no leftover motion in the old direction")
    }

    @Test func fastNotchesAccelerate() {
        let cfg = ScrollConfig(pixelsPerNotch: 60, acceleration: 0.5, maxMultiplier: 3, accelerationWindow: 0.1)
        var slow = ScrollAnimator(config: cfg)
        var fast = ScrollAnimator(config: cfg)
        for i in 0..<5 {
            slow.addNotches(vertical: 1, horizontal: 0, at: Double(i) * 0.5)
            fast.addNotches(vertical: 1, horizontal: 0, at: Double(i) * 0.02)
        }
        #expect(slow.pending.vertical == 300)
        // multipliers 1, 1.5, 2, 2.5, 3 → 60 * 10
        #expect(fast.pending.vertical == 600)
    }

    @Test func accelerationIsCapped() {
        let cfg = ScrollConfig(pixelsPerNotch: 60, acceleration: 2, maxMultiplier: 2, accelerationWindow: 0.1)
        var a = ScrollAnimator(config: cfg)
        for i in 0..<4 { a.addNotches(vertical: 1, horizontal: 0, at: Double(i) * 0.01) }
        // 1 + 2 + 2 + 2
        #expect(a.pending.vertical == 60 * 7)
    }

    @Test func queuedDistanceIsBounded() {
        let cfg = ScrollConfig(pixelsPerNotch: 60, acceleration: 2, maxMultiplier: 4)
        var a = ScrollAnimator(config: cfg)
        for i in 0..<10_000 { a.addNotches(vertical: 1, horizontal: 0, at: Double(i) * 0.001) }
        #expect(abs(a.pending.vertical) <= 60 * 4 * 20)
    }

    @Test func garbageInputIsIgnored() {
        var a = ScrollAnimator()
        a.addNotches(vertical: .nan, horizontal: .infinity, at: 0)
        #expect(a.isIdle)
        a.addNotches(vertical: 1, horizontal: 0, at: 0)
        // Huge / negative / NaN frame times must not explode or reverse.
        let big = a.step(dt: 1000)
        let neg = a.step(dt: -5)
        let nan = a.step(dt: .nan)
        #expect(big.vertical > 0 && big.vertical <= 60)
        #expect(neg == .zero)
        #expect(nan == .zero)
    }

    @Test func configIsSanitized() {
        let a = ScrollAnimator(config: ScrollConfig(pixelsPerNotch: -10, smoothing: 0, acceleration: .nan, maxMultiplier: 1e9))
        #expect(a.config.pixelsPerNotch == 5)
        #expect(a.config.smoothing == 0.02)
        #expect(a.config.acceleration == 0)
        #expect(a.config.maxMultiplier == 10)
    }

    @Test func resetStopsEverything() {
        var a = ScrollAnimator()
        a.addNotches(vertical: 3, horizontal: -2, at: 0)
        a.reset()
        #expect(a.isIdle)
        #expect(a.step(dt: 1 / 60) == .zero)
    }

    @Test func presetsProduceValidConfigs() {
        for speed in SpeedPreset.allCases {
            for smooth in SmoothnessPreset.allCases {
                let cfg = ScrollConfig(pixelsPerNotch: speed.pixelsPerNotch, smoothing: smooth.smoothing)
                #expect(cfg == cfg.sanitized())
            }
        }
    }
}

@Suite struct NotchRateLimitTests {
    @Test func fastSpinKeepsOneNotchPerInterval() {
        var animator = ScrollAnimator(config: ScrollConfig(acceleration: 0, minNotchInterval: 0.035))
        // 10 ms between events for 100 ms: only t = 0, 40, 80 ms are accepted.
        for i in 0...10 { animator.addNotches(vertical: 1, horizontal: 0, at: Double(i) * 0.01) }
        #expect(animator.pending.vertical == 180)
    }

    @Test func reversalIsNeverDropped() {
        var animator = ScrollAnimator(config: ScrollConfig(acceleration: 0, minNotchInterval: 0.04))
        animator.addNotches(vertical: 1, horizontal: 0, at: 0)
        animator.addNotches(vertical: -1, horizontal: 0, at: 0.001)
        #expect(animator.pending.vertical == -60)
    }

    @Test func disabledLimitKeepsEveryNotch() {
        var animator = ScrollAnimator(config: ScrollConfig(acceleration: 0))
        for i in 0...4 { animator.addNotches(vertical: 1, horizontal: 0, at: Double(i) * 0.005) }
        #expect(animator.pending.vertical == 300)
    }
}

@Suite struct AppProfileTests {
    @Test func profileRoundTripsThroughJSON() throws {
        let profile = AppProfile(bundleID: "com.example.game", name: "Game", excluded: true, limitRate: true)
        let data = try JSONEncoder().encode([profile])
        #expect(try JSONDecoder().decode([AppProfile].self, from: data) == [profile])
    }

    @Test func configHonoursAccelerationAndRateLimit() {
        var profile = AppProfile(bundleID: "a", name: "A", accelerate: false, limitRate: true, minNotchMs: 50)
        #expect(profile.scrollConfig.acceleration == 0)
        #expect(profile.scrollConfig.minNotchInterval == 0.05)
        profile.limitRate = false
        #expect(profile.scrollConfig.minNotchInterval == 0)
    }
}
