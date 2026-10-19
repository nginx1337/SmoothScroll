import Testing
@testable import SmoothScrollCore

private func wheel(
    synthetic: Bool = false, continuous: Bool = false, modifier: Bool = false,
    v: Int64 = 1, h: Int64 = 0, shift: Bool = false
) -> WheelEventInfo {
    WheelEventInfo(isSynthetic: synthetic, isContinuous: continuous, hasGestureModifier: modifier,
                   deltaVertical: v, deltaHorizontal: h, hasShift: shift)
}

@Suite struct ScrollEventFilterTests {
    @Test func plainWheelNotchIsSmoothed() {
        #expect(ScrollEventFilter.decide(wheel(v: -1), enabled: true) == .smooth(vertical: -1, horizontal: 0))
        #expect(ScrollEventFilter.decide(wheel(v: 0, h: 1), enabled: true) == .smooth(vertical: 0, horizontal: 1))
    }

    @Test func disabledPassesEverything() {
        #expect(ScrollEventFilter.decide(wheel(), enabled: false) == .passThrough)
    }

    @Test func ownEventsAreNeverReprocessed() {
        // Otherwise posted pixels would loop back into the animator.
        #expect(ScrollEventFilter.decide(wheel(synthetic: true), enabled: true) == .passThrough)
    }

    @Test func trackpadAndMagicMouseAreUntouched() {
        #expect(ScrollEventFilter.decide(wheel(continuous: true), enabled: true) == .passThrough)
    }

    @Test func gestureModifiersAreUntouched() {
        #expect(ScrollEventFilter.decide(wheel(modifier: true), enabled: true) == .passThrough)
    }

    @Test func zeroDeltaPassesThrough() {
        #expect(ScrollEventFilter.decide(wheel(v: 0, h: 0), enabled: true) == .passThrough)
    }

    @Test func coalescedNotchesKeepMagnitude() {
        #expect(ScrollEventFilter.decide(wheel(v: 3), enabled: true) == .smooth(vertical: 3, horizontal: 0))
    }

    @Test func shiftTurnsVerticalWheelIntoHorizontal() {
        #expect(ScrollEventFilter.decide(wheel(v: -2, shift: true), enabled: true) == .smooth(vertical: 0, horizontal: -2))
        #expect(wheel(v: 1, shift: true).shiftScrollsHorizontally)
    }

    @Test func shiftLeavesExistingHorizontalAlone() {
        // A tilt wheel already reports horizontal motion; don't swap it.
        #expect(ScrollEventFilter.decide(wheel(v: 0, h: 1, shift: true), enabled: true) == .smooth(vertical: 0, horizontal: 1))
        #expect(!wheel(v: 0, h: 1, shift: true).shiftScrollsHorizontally)
    }

    @Test func notchesPerEventAreCapped() {
        let cap = Double(ScrollEventFilter.maxNotchesPerEvent)
        #expect(ScrollEventFilter.decide(wheel(v: 50, h: -50), enabled: true) == .smooth(vertical: cap, horizontal: -cap))
        #expect(ScrollEventFilter.decide(wheel(v: .min), enabled: true) == .smooth(vertical: -cap, horizontal: 0))
    }
}
