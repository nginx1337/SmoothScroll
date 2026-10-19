import AppKit
import CoreGraphics
import QuartzCore
import SmoothScrollCore

/// Tag stamped on every event we post so the tap lets it through.
let syntheticEventMarker: Int64 = 0x534D_4F4F_5448 // "SMOOTH"

/// Intercepts discrete mouse-wheel events with a session event tap, swallows
/// them, and replays the same distance as a smooth stream of pixel scroll
/// events driven by the display refresh rate.
///
/// The tap runs on its own high-priority thread, so a busy main thread never
/// delays scrolling system-wide (trackpad events pass through that thread
/// too). Only the animation lives on the main thread.
///
/// Which events are touched is decided by `ScrollEventFilter`: trackpads,
/// Magic Mouse and anything with ⌘/⌃/⌥ held always pass through.
@MainActor
final class ScrollInterceptor: NSObject {
    var config: ScrollConfig {
        get { animator.config }
        set { animator.config = newValue }
    }

    var isEnabled = true {
        didSet {
            context.enabled = isEnabled
            if !isEnabled { stopAnimation() }
        }
    }

    /// Stop the glide when the pointer moves to another window. When off,
    /// the rest of the glide scrolls whatever is under the pointer.
    var stopsOnWindowChange = true

    private(set) var isRunning = false

    private let context = TapContext()
    private var animator = ScrollAnimator()
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    /// Uptime of the last notch or frame; used to detect a stalled display link.
    private var lastActivity: TimeInterval = 0
    private var observers: [NSObjectProtocol] = []

    // Captured from the latest real wheel event.
    private var targetFlags: CGEventFlags = []
    private var targetWindow = 0
    private var lastPointer = CGPoint(x: CGFloat.nan, y: .nan)
    private var lastPointerWindow = 0

    /// A glide that has produced no frame for this long gets a fresh display
    /// link on the next notch.
    private static let stallTimeout: TimeInterval = 0.25

    override init() {
        super.init()
        context.onWheel = { [weak self] notch in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handleWheel(notch) }
            }
        }
    }

    /// Installs the event tap. Fails (returns false) without Accessibility access.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollTapCallback,
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        ) else {
            return false
        }
        context.enabled = isEnabled
        context.startThread(port: port)
        observeSystemEvents()
        isRunning = true
        return true
    }

    func stop() {
        stopAnimation()
        context.stopThread()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        isRunning = false
    }

    /// Called on the main thread for every wheel event the filter swallowed.
    private func handleWheel(_ notch: WheelNotch) {
        guard isEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if displayLink != nil && now - lastActivity > Self.stallTimeout {
            // No frame for a while: the link may be dead, or the main thread
            // was just busy. Recreate the link below but keep the distance;
            // a genuinely stale glide is already dropped by the screen
            // sleep/change observers.
            displayLink?.invalidate()
            displayLink = nil
        }
        let window = windowUnderPointer()
        if stopsOnWindowChange && window != targetWindow {
            // Never carry an old glide over into a different window.
            animator.reset()
        }
        targetWindow = window
        // Timestamped on the tap thread, so a busy main thread delivering
        // several queued notches at once can't fake a fast spin.
        animator.addNotches(vertical: notch.vertical, horizontal: notch.horizontal, at: notch.time)
        targetFlags = notch.flags
        lastActivity = now
        startAnimation()
    }

    // MARK: - Animation

    private func startAnimation() {
        guard displayLink == nil else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let link = screen?.displayLink(target: self, selector: #selector(frame(_:))) else {
            // No display (e.g. headless); fall back to posting everything at once.
            flushImmediately()
            return
        }
        lastFrameTime = 0
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        animator.reset()
    }

    @objc private func frame(_ link: CADisplayLink) {
        // The pointer moved to another window: stop instead of scrolling
        // something the wheel was never turned over.
        if stopsOnWindowChange && windowUnderPointerIfMoved() != targetWindow {
            stopAnimation()
            return
        }

        let now = link.timestamp
        let dt = lastFrameTime == 0 ? link.duration : now - lastFrameTime
        lastFrameTime = now
        lastActivity = ProcessInfo.processInfo.systemUptime

        let step = animator.step(dt: dt)
        if !step.isZero { post(step) }
        if animator.isIdle {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func flushImmediately() {
        var guardCounter = 0
        while !animator.isIdle && guardCounter < 1000 {
            let step = animator.step(dt: 1.0 / 15.0)
            if !step.isZero { post(step) }
            guardCounter += 1
        }
        animator.reset()
    }

    private func post(_ step: ScrollStep) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: step.vertical,
            wheel2: step.horizontal,
            wheel3: 0
        ) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        // Location is deliberately left as created (the current pointer
        // position): posting an event with an explicit location warps the
        // cursor there. Leaving the target window is handled in `frame`.
        // ⇧-scroll arrives here already converted to the horizontal axis.
        event.flags = targetFlags
        event.post(tap: .cgSessionEventTap)
    }

    private func windowUnderPointer() -> Int {
        let location = NSEvent.mouseLocation
        lastPointer = location
        lastPointerWindow = NSWindow.windowNumber(at: location, belowWindowWithWindowNumber: 0)
        return lastPointerWindow
    }

    /// Per-frame variant: the window-server hit test only runs when the
    /// pointer actually moved since the last lookup.
    private func windowUnderPointerIfMoved() -> Int {
        NSEvent.mouseLocation == lastPointer ? lastPointerWindow : windowUnderPointer()
    }

    /// Drop in-flight glides when displays sleep or change, so a leftover
    /// distance can't fire later.
    private func observeSystemEvents() {
        let stop: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAnimation() }
        }
        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: stop),
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: stop),
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: stop),
        ]
    }
}

// MARK: - Event tap thread

/// One swallowed wheel event, handed from the tap thread to the main thread.
private struct WheelNotch: Sendable {
    var vertical: Double
    var horizontal: Double
    var flags: CGEventFlags
    /// Uptime when the tap saw the event, not when the main thread got it.
    var time: TimeInterval
}

/// State shared between the main thread and the event-tap thread.
/// Every mutable field is guarded by `lock`.
private final class TapContext: @unchecked Sendable {
    private let lock = NSLock()
    private var _enabled = true
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?

    /// Set once at init on the main thread, read on the tap thread.
    var onWheel: @Sendable (WheelNotch) -> Void = { _ in }

    var enabled: Bool {
        get { lock.withLock { _enabled } }
        set { lock.withLock { _enabled = newValue } }
    }

    func startThread(port: CFMachPort) {
        lock.withLock { self.port = port }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            // Read the port through the lock rather than capturing it:
            // CFMachPort isn't Sendable.
            guard let port = lock.withLock({ self.port }) else { ready.signal(); return }
            let loop = CFRunLoopGetCurrent()
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            lock.withLock { runLoop = loop }
            ready.signal()
            CFRunLoopRun() // returns after stopThread()
        }
        thread.name = "SmoothScroll event tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    func stopThread() {
        let (port, loop) = lock.withLock {
            defer { self.port = nil; self.runLoop = nil }
            return (self.port, self.runLoop)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port) // also removes its run loop source
        }
        if let loop { CFRunLoopStop(loop) }
    }

    /// Runs on the tap thread: the system disables slow or interrupted taps.
    func reenable() {
        if let port = lock.withLock({ port }) { CGEvent.tapEnable(tap: port, enable: true) }
    }
}

/// C callback for the event tap; runs on the tap thread. Must stay fast:
/// every scroll event on the system waits for it.
private func scrollTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let pass = Unmanaged.passUnretained(event)
    guard let userInfo else { return pass }
    let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        context.reenable()
        return pass
    case .scrollWheel:
        break
    default:
        return pass
    }

    var flags = event.flags
    let info = WheelEventInfo(
        isSynthetic: event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker,
        isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
        hasGestureModifier: !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
        deltaVertical: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
        deltaHorizontal: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
        hasShift: flags.contains(.maskShift)
    )
    switch ScrollEventFilter.decide(info, enabled: context.enabled) {
    case .passThrough:
        return pass
    case let .smooth(vertical, horizontal):
        // The axes are already swapped; a leftover ⇧ could make an app swap
        // them back or treat the scroll specially.
        if info.shiftScrollsHorizontally { flags.remove(.maskShift) }
        context.onWheel(WheelNotch(
            vertical: vertical, horizontal: horizontal, flags: flags,
            time: ProcessInfo.processInfo.systemUptime
        ))
        return nil
    }
}
