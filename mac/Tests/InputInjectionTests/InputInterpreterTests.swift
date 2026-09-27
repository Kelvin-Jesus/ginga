import CoreGraphics
import GingaProtocol
import Testing
@testable import InputInjection

@Suite("InputInterpreter")
struct InputInterpreterTests {
    /// The virtual display at x = -1280 (left of the main display), 1280×800 points.
    let bounds = CGRect(x: -1280, y: 0, width: 1280, height: 800)

    private func touch(_ action: InputAction, at points: [(UInt16, UInt16)], t: UInt64) -> InputMessage {
        InputMessage(sequence: 0, eventTimeUs: t, kind: .touch, action: action,
                     pointers: points.enumerated().map { PointerRecord(pointerId: UInt8($0.offset), toolType: .finger, x: $0.element.0, y: $0.element.1, pressure: 30000) })
    }

    private func pen(_ action: InputAction, x: UInt16, y: UInt16, pressure: UInt16 = 0, buttons: PointerButtons = [], tiltX: Int16 = 0, tiltY: Int16 = 0,
                     tool: ToolType = .stylus, kind: InputKind = .stylus) -> InputMessage {
        InputMessage(sequence: 0, eventTimeUs: 0, kind: kind, action: action,
                     pointers: [PointerRecord(pointerId: 0, toolType: tool, buttons: buttons, x: x, y: y, pressure: pressure, tiltX: tiltX, tiltY: tiltY)])
    }

    @Test func normalizedCoordinatesMapIntoTheDisplayBounds() {
        let interpreter = InputInterpreter(bounds: bounds)
        #expect(interpreter.point(x: 0, y: 0) == CGPoint(x: -1280, y: 0))
        #expect(interpreter.point(x: 65535, y: 65535) == CGPoint(x: -1, y: 799))
        let centre = interpreter.point(x: 32768, y: 32768)
        #expect(abs(centre.x - (-640)) < 1 && abs(centre.y - 400) < 1)
    }

    @Test func tapBecomesALeftClickAtTheTouchPoint() {
        var interpreter = InputInterpreter(bounds: bounds)
        let p = interpreter.point(x: 1000, y: 1000)
        #expect(interpreter.interpret(touch(.down, at: [(1000, 1000)], t: 0)) == [.move(p, pen: nil)])
        #expect(interpreter.interpret(touch(.up, at: [(1000, 1000)], t: 90_000)) == [.down(.left, p, pen: nil), .up(.left, p, pen: nil)])
    }

    @Test func longPressBecomesARightClick() {
        var interpreter = InputInterpreter(bounds: bounds)
        let p = interpreter.point(x: 1000, y: 1000)
        _ = interpreter.interpret(touch(.down, at: [(1000, 1000)], t: 0))
        #expect(interpreter.interpret(touch(.up, at: [(1000, 1000)], t: 700_000)) == [.down(.right, p, pen: nil), .up(.right, p, pen: nil)])
    }

    @Test func smallJitterStaysAClickButMovementBecomesADrag() {
        var interpreter = InputInterpreter(bounds: bounds)
        let start = interpreter.point(x: 10000, y: 10000)
        _ = interpreter.interpret(touch(.down, at: [(10000, 10000)], t: 0))
        #expect(interpreter.interpret(touch(.move, at: [(10100, 10000)], t: 10_000)).isEmpty)  // ~2 pt
        let moved = interpreter.point(x: 14000, y: 10000)
        #expect(interpreter.interpret(touch(.move, at: [(14000, 10000)], t: 20_000)) == [.down(.left, start, pen: nil), .drag(.left, moved, pen: nil)])
        #expect(interpreter.interpret(touch(.up, at: [(14000, 10000)], t: 30_000)) == [.up(.left, moved, pen: nil)])
    }

    @Test func twoFingersScrollWithPhasesAndNoClick() {
        var interpreter = InputInterpreter(bounds: bounds)
        _ = interpreter.interpret(touch(.down, at: [(20000, 20000)], t: 0))
        #expect(interpreter.interpret(touch(.pointerDown, at: [(20000, 20000), (30000, 20000)], t: 5_000)) == [.scroll(dx: 0, dy: 0, phase: .began)])
        let events = interpreter.interpret(touch(.move, at: [(20000, 25000), (30000, 25000)], t: 10_000))
        guard case .scroll(let dx, let dy, .changed)? = events.first else {
            Issue.record("expected a scroll, got \(events)")
            return
        }
        #expect(abs(dx) < 0.01)
        #expect(abs(dy - Double(5000) / 65535 * 799) < 0.01)  // fingers moved down → content follows
        #expect(interpreter.interpret(touch(.pointerUp, at: [(20000, 25000), (30000, 25000)], t: 20_000)) == [.scroll(dx: 0, dy: 0, phase: .ended)])
        #expect(interpreter.interpret(touch(.up, at: [(20000, 25000)], t: 30_000)).isEmpty)
    }

    @Test func cancelReleasesAHeldButton() {
        var interpreter = InputInterpreter(bounds: bounds)
        _ = interpreter.interpret(touch(.down, at: [(10000, 10000)], t: 0))
        _ = interpreter.interpret(touch(.move, at: [(20000, 10000)], t: 1_000))
        let events = interpreter.interpret(touch(.cancel, at: [(20000, 10000)], t: 2_000))
        #expect(events.count == 1)
        if case .up(.left, _, _)? = events.first {} else { Issue.record("expected left up, got \(events)") }
    }

    /// The receiver vanished mid-drag (cable pulled, app replaced): nothing may stay pressed.
    @Test func resetReleasesWhateverIsHeld() {
        var interpreter = InputInterpreter(bounds: bounds)
        _ = interpreter.interpret(touch(.down, at: [(10000, 10000)], t: 0))
        _ = interpreter.interpret(touch(.move, at: [(14000, 10000)], t: 10_000))
        let last = interpreter.point(x: 14000, y: 10000)
        #expect(interpreter.reset() == [.up(.left, last, pen: nil)])
        #expect(interpreter.reset().isEmpty)  // idle now

        _ = interpreter.interpret(touch(.down, at: [(20000, 20000)], t: 0))
        _ = interpreter.interpret(touch(.pointerDown, at: [(20000, 20000), (30000, 20000)], t: 5_000))
        #expect(interpreter.reset() == [.scroll(dx: 0, dy: 0, phase: .ended)])

        let tip = interpreter.point(x: 5000, y: 5000)
        _ = interpreter.interpret(pen(.down, x: 5000, y: 5000, pressure: 30000))
        #expect(interpreter.reset() == [.up(.left, tip, pen: nil), .penProximity(entering: false)])
    }

    /// An `up` lost on the way (e.g. across a reconnect) must not leave the button down when the
    /// next gesture starts.
    @Test func aNewGestureFirstReleasesAButtonLeftDown() {
        var interpreter = InputInterpreter(bounds: bounds)
        _ = interpreter.interpret(touch(.down, at: [(10000, 10000)], t: 0))
        _ = interpreter.interpret(touch(.move, at: [(14000, 10000)], t: 10_000))
        let last = interpreter.point(x: 14000, y: 10000)
        let next = interpreter.point(x: 30000, y: 30000)
        #expect(interpreter.interpret(touch(.down, at: [(30000, 30000)], t: 50_000)) == [.up(.left, last, pen: nil), .move(next, pen: nil)])

        let first = interpreter.point(x: 5000, y: 5000)
        _ = interpreter.interpret(pen(.down, x: 5000, y: 5000, pressure: 30000))
        let second = interpreter.interpret(pen(.down, x: 6000, y: 6000, pressure: 30000))
        #expect(second.first == .up(.left, first, pen: nil))
        #expect(second.count == 2)
    }

    @Test func penDrawsWithPressureAndTilt() {
        var interpreter = InputInterpreter(bounds: bounds)
        let p = interpreter.point(x: 5000, y: 6000)
        let hover = SyntheticPointerEvent.Pen(pressure: 0, tiltX: 0, tiltY: 0)
        #expect(interpreter.interpret(pen(.hoverEnter, x: 5000, y: 6000)) == [.penProximity(entering: true), .move(p, pen: hover)])
        let down = interpreter.interpret(pen(.down, x: 5000, y: 6000, pressure: 32768, tiltX: 16384, tiltY: -16384))
        guard case .down(.left, p, let penState?)? = down.first else {
            Issue.record("expected pen down, got \(down)")
            return
        }
        #expect(abs(penState.pressure - 0.5) < 0.001)
        #expect(abs(penState.tiltX - 0.5) < 0.001 && abs(penState.tiltY + 0.5) < 0.001)
        if case .drag(.left, _, _)? = interpreter.interpret(pen(.move, x: 5100, y: 6000, pressure: 40000)).first {} else { Issue.record("expected drag") }
        if case .up(.left, _, _)? = interpreter.interpret(pen(.up, x: 5100, y: 6000)).first {} else { Issue.record("expected up") }
        #expect(interpreter.interpret(pen(.hoverExit, x: 5100, y: 6000)) == [.penProximity(entering: false)])
    }

    @Test func penSideButtonUsesTheRightButton() {
        var interpreter = InputInterpreter(bounds: bounds)
        let events = interpreter.interpret(pen(.down, x: 1, y: 1, pressure: 1000, buttons: [.stylusPrimary]))
        #expect(events.first == .penProximity(entering: true))  // touched down without hovering first
        if case .down(.right, _, _)? = events.last {} else { Issue.record("expected right down, got \(events)") }
        if case .up(.right, _, _)? = interpreter.interpret(pen(.up, x: 1, y: 1)).first {} else { Issue.record("expected right up") }
    }

    /// Like Sidecar's Apple Pencil: a pen tablet to macOS, so drawing apps get pressure, tilt and
    /// the eraser, hovering included.
    @Test func thePenIsAPenTabletWithAnEraser() {
        var interpreter = InputInterpreter(bounds: bounds)
        let hovering = interpreter.interpret(pen(.hoverMove, x: 100, y: 100, tiltX: 16384))
        #expect(hovering.first == .penProximity(entering: true))
        if case .move(_, let state?)? = hovering.last {
            #expect(state.pressure == 0 && abs(state.tiltX - 0.5) < 0.001)
        } else {
            Issue.record("expected a hover move with tilt, got \(hovering)")
        }
        // Eraser end: leave as the pen, come back as the eraser.
        let erasing = interpreter.interpret(pen(.down, x: 100, y: 100, pressure: 20000, tool: .eraser))
        #expect(Array(erasing.prefix(2)) == [.penProximity(entering: false), .penProximity(entering: true, eraser: true)])
        if case .down(.left, _, let state?)? = erasing.last { #expect(state.isEraser) } else { Issue.record("expected an eraser down") }
        _ = interpreter.interpret(pen(.up, x: 100, y: 100, tool: .eraser))
        #expect(interpreter.interpret(pen(.hoverExit, x: 100, y: 100, tool: .eraser)) == [.penProximity(entering: false, eraser: true)])
        #expect(interpreter.interpret(pen(.hoverExit, x: 100, y: 100)).isEmpty)  // already out of range
    }

    @Test func aMouseOnTheTabletStaysAMouse() {
        var interpreter = InputInterpreter(bounds: bounds)
        let p = interpreter.point(x: 100, y: 100)
        #expect(interpreter.interpret(pen(.hoverMove, x: 100, y: 100, tool: .mouse, kind: .mouse)) == [.move(p, pen: nil)])
        #expect(interpreter.interpret(pen(.down, x: 100, y: 100, pressure: 65535, tool: .mouse, kind: .mouse)) == [.down(.left, p, pen: nil)])
    }

    /// A flick keeps scrolling after the fingers leave (like a trackpad); a pause before lifting
    /// doesn't, and the next touch stops a running one.
    @Test func aFlickLeavesInertiaAndATouchStopsIt() {
        var interpreter = InputInterpreter(bounds: bounds)
        _ = interpreter.interpret(touch(.down, at: [(20000, 20000)], t: 0))
        _ = interpreter.interpret(touch(.pointerDown, at: [(20000, 20000), (30000, 20000)], t: 1_000))
        var y: UInt16 = 20000
        for step in 1...6 {
            y += 1000  // 1000/65535 of 800 pt ≈ 12 pt per 16 ms ≈ 760 pt/s
            _ = interpreter.interpret(touch(.move, at: [(20000, y), (30000, y)], t: UInt64(step) * 16_000))
        }
        let lifted = interpreter.interpret(touch(.up, at: [(20000, y)], t: 7 * 16_000))
        #expect(lifted.first == .scroll(dx: 0, dy: 0, phase: .ended))
        guard case .momentum(let vx, let vy)? = lifted.last else {
            Issue.record("expected inertia, got \(lifted)")
            return
        }
        #expect(abs(vx) < 1 && vy > 500 && vy < 1000)
        #expect(interpreter.interpret(touch(.down, at: [(1000, 1000)], t: 8 * 16_000)).first == .stopMomentum)
    }

    @Test func aPauseBeforeLiftingLeavesNoInertia() {
        var interpreter = InputInterpreter(bounds: bounds)
        _ = interpreter.interpret(touch(.down, at: [(20000, 20000)], t: 0))
        _ = interpreter.interpret(touch(.pointerDown, at: [(20000, 20000), (30000, 20000)], t: 1_000))
        _ = interpreter.interpret(touch(.move, at: [(20000, 25000), (30000, 25000)], t: 16_000))
        let lifted = interpreter.interpret(touch(.up, at: [(20000, 25000)], t: 400_000))  // held still 384 ms
        #expect(lifted == [.scroll(dx: 0, dy: 0, phase: .ended)])
        #expect(interpreter.interpret(touch(.down, at: [(1000, 1000)], t: 500_000)).first != .stopMomentum)
    }

    /// Sidecar-style: one finger neither moves the pointer nor clicks; two fingers still scroll.
    @Test func inGesturesModeOneFingerDoesNothing() {
        var interpreter = InputInterpreter(bounds: bounds)
        interpreter.touchMode = .gestures
        #expect(interpreter.interpret(touch(.down, at: [(10000, 10000)], t: 0)).isEmpty)
        #expect(interpreter.interpret(touch(.move, at: [(20000, 10000)], t: 10_000)).isEmpty)
        #expect(interpreter.interpret(touch(.up, at: [(20000, 10000)], t: 20_000)).isEmpty)
        _ = interpreter.interpret(touch(.down, at: [(20000, 20000)], t: 100_000))
        #expect(interpreter.interpret(touch(.pointerDown, at: [(20000, 20000), (30000, 20000)], t: 101_000)) == [.scroll(dx: 0, dy: 0, phase: .began)])
    }
}
