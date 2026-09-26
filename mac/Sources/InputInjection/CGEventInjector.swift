import CoreGraphics
import Foundation
import os
import Tab2MacCore
import Tab2MacProtocol

extension Log {
    public static let input = Logger(subsystem: subsystem, category: "input")
}

/// Posts synthetic pointer events with CoreGraphics.
///
/// Requires the "Post Event" privilege (System Settings › Privacy & Security › Accessibility
/// lists the app once requested). Without it macOS silently ignores the events.
public final class CGEventInjector: @unchecked Sendable {  // `lastClick` is guarded by `lock`; CGEventSource is only read
    public static var hasPermission: Bool { CGPreflightPostEventAccess() }

    /// Shows the system prompt the first time; returns the current state.
    @discardableResult
    public static func requestPermission() -> Bool { CGRequestPostEventAccess() }

    private let source: CGEventSource?
    private let lock = NSLock()
    private var lastClick: (time: Date, location: CGPoint, button: SyntheticPointerEvent.Button, count: Int)?

    public init() {
        source = CGEventSource(stateID: .hidSystemState)
        // Don't suppress the user's own hardware input after each synthetic event.
        source?.localEventsSuppressionInterval = 0
    }

    public func post(_ events: [SyntheticPointerEvent]) {
        events.forEach(post)
    }

    public func post(_ event: SyntheticPointerEvent) {
        switch event {
        case .move(let location, let pen):
            mouse(.mouseMoved, location, button: .left, pen: pen)
        case .down(let button, let location, let pen):
            let clickCount = registerClick(button: button, at: location)
            mouse(button == .left ? .leftMouseDown : .rightMouseDown, location, button: button, pen: pen, clickCount: clickCount)
        case .drag(let button, let location, let pen):
            mouse(button == .left ? .leftMouseDragged : .rightMouseDragged, location, button: button, pen: pen)
        case .up(let button, let location, let pen):
            let clickCount = lock.withLock { lastClick?.count ?? 1 }
            mouse(button == .left ? .leftMouseUp : .rightMouseUp, location, button: button, pen: pen, clickCount: clickCount)
        case .scroll(let dx, let dy, let phase):
            scroll(dx: dx, dy: dy, phase: phase)
        case .penProximity(let entering, let eraser):
            proximity(entering: entering, eraser: eraser)
        case .momentum(let vx, let vy):
            startMomentum(vx: vx, vy: vy)
        case .stopMomentum:
            stopMomentum()
        }
    }

    private func mouse(_ type: CGEventType, _ location: CGPoint, button: SyntheticPointerEvent.Button, pen: SyntheticPointerEvent.Pen?, clickCount: Int = 1) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button == .left ? .left : .right) else { return }
        if type != .mouseMoved { event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount)) }
        if let pen {
            // A tablet point tied to the proximity event's device: apps read pressure and tilt.
            event.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletPoint.rawValue))
            event.setDoubleValueField(.mouseEventPressure, value: pen.pressure)
            event.setDoubleValueField(.tabletEventPointPressure, value: pen.pressure)
            event.setDoubleValueField(.tabletEventTiltX, value: pen.tiltX)
            event.setDoubleValueField(.tabletEventTiltY, value: pen.tiltY)
            event.setIntegerValueField(.tabletEventDeviceID, value: Self.penDeviceID)
            event.setIntegerValueField(.tabletEventPointButtons, value: type == .mouseMoved ? 0 : 1)
        }
        event.post(tap: .cghidEventTap)
    }

    /// Identifies the S Pen as a pen tablet's pointer, the way a Wacom driver (or Sidecar's Apple
    /// Pencil) does: the same device ID ties the tablet points that follow to this pen.
    static let penDeviceID: Int64 = 0x7432
    private static let penVendorID: Int64 = 0x5022  // Tab2Mac's display vendor ID
    /// Device ID, absolute X/Y, buttons, tilt X/Y and pressure (NX_TABLET_CAPABILITY_* bits).
    private static let penCapabilities: Int64 = 0x0001 | 0x0002 | 0x0004 | 0x0040 | 0x0080 | 0x0100 | 0x0400

    private func proximity(entering: Bool, eraser: Bool) {
        guard let event = CGEvent(source: source) else { return }
        event.type = .tabletProximity
        event.location = CGEvent(source: nil)?.location ?? .zero
        event.setIntegerValueField(.tabletProximityEventVendorID, value: Self.penVendorID)
        event.setIntegerValueField(.tabletProximityEventTabletID, value: 1)
        event.setIntegerValueField(.tabletProximityEventPointerID, value: eraser ? 2 : 1)
        event.setIntegerValueField(.tabletProximityEventDeviceID, value: Self.penDeviceID)
        event.setIntegerValueField(.tabletProximityEventSystemTabletID, value: 1)
        event.setIntegerValueField(.tabletProximityEventVendorPointerType, value: eraser ? 0x080A : 0x0802)
        event.setIntegerValueField(.tabletProximityEventVendorPointerSerialNumber, value: 1)
        event.setIntegerValueField(.tabletProximityEventVendorUniqueID, value: 0x7432_0001)
        event.setIntegerValueField(.tabletProximityEventCapabilityMask, value: Self.penCapabilities)
        event.setIntegerValueField(.tabletProximityEventPointerType, value: eraser ? 3 : 1)  // NX_TABLET_POINTER_ERASER : _PEN
        event.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
        event.post(tap: .cghidEventTap)
    }

    private func scroll(dx: Double, dy: Double, phase: SyntheticPointerEvent.ScrollPhase) {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let phaseValue: Int64 = switch phase {
        case .began: 1   // kCGScrollPhaseBegan
        case .changed: 2 // kCGScrollPhaseChanged
        case .ended: 4   // kCGScrollPhaseEnded
        }
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phaseValue)
        event.post(tap: .cghidEventTap)
    }

    // MARK: Keyboard

    private var heldKeys: Set<CGKeyCode> = []  // guarded by `lock`

    /// A key from the tablet's keyboard. Modifiers become flag changes, as from a real keyboard.
    public func postKey(_ key: KeyMessage, mapper: KeyboardMapper) {
        guard let code = mapper.virtualKey(forUsage: key.usage) else { return }
        let down = key.action == .down
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        if KeyboardMapper.isModifier(key.usage) { event.type = .flagsChanged }
        event.flags = mapper.flags(for: key.modifiers)
        let repeated = lock.withLock { () -> Bool in
            if down { return !heldKeys.insert(code).inserted }
            heldKeys.remove(code)
            return false
        }
        if repeated { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        event.post(tap: .cghidEventTap)
    }

    /// The keyboard went away with a key held: release it, so nothing stays pressed on the Mac.
    public func releaseKeys() {
        let held = lock.withLock { () -> Set<CGKeyCode> in
            defer { heldKeys = [] }
            return heldKeys
        }
        for code in held {
            CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Inertia

    private let momentumQueue = DispatchQueue(label: "dev.tab2mac.input.momentum", qos: .userInteractive)
    private var momentumTimer: DispatchSourceTimer?  // guarded by `lock`

    /// Keeps scrolling after a flick and slows down like a trackpad (momentum phases, so apps
    /// that tell inertia apart, e.g. to rubber-band at an edge, do). Runs only while it moves.
    private func startMomentum(vx: Double, vy: Double) {
        stopMomentum()
        let interval = 1.0 / 120
        var velocity = (x: vx, y: vy)
        var remainder = (x: 0.0, y: 0.0)  // sub-pixel movement carried to the next event
        var phase: Int64 = 1  // kCGMomentumScrollPhaseBegin
        let timer = DispatchSource.makeTimerSource(queue: momentumQueue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
            if speed < 20 {
                self.postMomentum(dx: 0, dy: 0, phase: 3)  // kCGMomentumScrollPhaseEnd
                self.lock.withLock {
                    self.momentumTimer?.cancel()
                    self.momentumTimer = nil
                }
                return
            }
            let dx = velocity.x * interval + remainder.x, dy = velocity.y * interval + remainder.y
            remainder = (dx - dx.rounded(), dy - dy.rounded())
            self.postMomentum(dx: dx, dy: dy, phase: phase)
            phase = 2  // kCGMomentumScrollPhaseContinue
            let decay = pow(0.95, interval * 60)  // about 5 % per 60 Hz frame, as a trackpad
            velocity = (velocity.x * decay, velocity.y * decay)
        }
        lock.withLock { momentumTimer = timer }
        timer.resume()
    }

    private func stopMomentum() {
        let running = lock.withLock { () -> DispatchSourceTimer? in
            defer { momentumTimer = nil }
            return momentumTimer
        }
        guard let running else { return }
        running.cancel()
        momentumQueue.async { self.postMomentum(dx: 0, dy: 0, phase: 3) }
    }

    private func postMomentum(dx: Double, dy: Double, phase: Int64) {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: phase)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
        event.post(tap: .cghidEventTap)
    }

    /// Double/triple clicks: same button, close in time and space.
    private func registerClick(button: SyntheticPointerEvent.Button, at location: CGPoint) -> Int {
        lock.withLock {
            let now = Date()
            var count = 1
            if let last = lastClick, last.button == button,
               now.timeIntervalSince(last.time) < NSEventDoubleClickInterval(),
               abs(last.location.x - location.x) < 6, abs(last.location.y - location.y) < 6 {
                count = last.count + 1
            }
            lastClick = (now, location, button, count)
            return count
        }
    }
}

private func NSEventDoubleClickInterval() -> TimeInterval {
    // NSEvent.doubleClickInterval without importing AppKit into this module.
    let value = UserDefaults.standard.double(forKey: "com.apple.mouse.doubleClickThreshold")
    return value > 0 ? value : 0.5
}
