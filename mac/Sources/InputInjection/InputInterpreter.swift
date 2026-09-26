import CoreGraphics
import Foundation
import Tab2MacProtocol

/// A pointer action to perform on the Mac, in global display coordinates (points, top-left origin).
public enum SyntheticPointerEvent: Equatable, Sendable {
    public struct Pen: Equatable, Sendable {
        /// 0…1
        public var pressure: Double
        /// −1…1 (fraction of 90°)
        public var tiltX: Double
        public var tiltY: Double
        /// The pen's eraser end (or eraser mode): drawing apps switch to their eraser.
        public var isEraser: Bool

        public init(pressure: Double, tiltX: Double, tiltY: Double, isEraser: Bool = false) {
            self.pressure = pressure
            self.tiltX = tiltX
            self.tiltY = tiltY
            self.isEraser = isEraser
        }
    }

    public enum Button: Equatable, Sendable { case left, right }
    public enum ScrollPhase: Equatable, Sendable { case began, changed, ended }

    case move(CGPoint, pen: Pen?)
    case down(Button, CGPoint, pen: Pen?)
    case drag(Button, CGPoint, pen: Pen?)
    case up(Button, CGPoint, pen: Pen?)
    /// Pixel deltas; positive `dy` = content moves down (fingers moving down), like a trackpad.
    case scroll(dx: Double, dy: Double, phase: ScrollPhase)
    /// The fingers left while moving: keep scrolling and slow down (points per second), as a
    /// trackpad's inertia does.
    case momentum(vx: Double, vy: Double)
    /// A new touch stops a running inertia scroll.
    case stopMomentum
    /// The pen came into (or left) range, as a pen tablet reports it: drawing apps treat the
    /// following events as a stylus (pressure, tilt, eraser) rather than a mouse.
    case penProximity(entering: Bool, eraser: Bool = false)
}

/// Turns protocol INPUT messages into Mac pointer actions (architecture §2.7):
/// tap → click · drag → drag · long press → right click · two fingers → scroll ·
/// S Pen → pressure/tilt drawing, hover moves the pointer, side button → right button.
///
/// Pure and deterministic (times come from the messages), so the mapping is unit-tested.
public struct InputInterpreter: Sendable {
    public var bounds: CGRect
    /// Movement (points) before a touch becomes a drag instead of a click.
    public var touchSlop: Double = 8
    /// Hold time before a stationary touch becomes a right click.
    public var longPressMicros: UInt64 = 550_000

    private enum TouchState: Sendable {
        case idle
        case pending(start: CGPoint, startTime: UInt64)
        case dragging(last: CGPoint)
        case scrolling(centroid: CGPoint)
    }

    /// What one finger does: point and click (default), or nothing, as in Sidecar, where fingers
    /// scroll and the pen points.
    public enum TouchMode: Sendable { case pointer, gestures }
    public var touchMode: TouchMode = .pointer

    private var touch: TouchState = .idle
    /// Recent scroll movement (event time µs, dx, dy), for the release velocity.
    private var scrollSamples: [(time: UInt64, dx: Double, dy: Double)] = []
    /// Until when (event time µs) an inertia scroll may still be running.
    private var momentumUntil: UInt64 = 0
    /// Slower than this (points/s) at release, the scroll just stops.
    public var momentumThreshold: Double = 150
    private var penButton: SyntheticPointerEvent.Button?
    /// In range, and as which end (nil: out of range).
    private var penProximity: Bool?
    private var penLocation: CGPoint?

    public init(bounds: CGRect) {
        self.bounds = bounds
    }

    /// Normalized 0…65535 coordinates → global point inside `bounds`.
    public func point(x: UInt16, y: UInt16) -> CGPoint {
        CGPoint(
            x: bounds.minX + (Double(x) / 65535) * max(bounds.width - 1, 0),
            y: bounds.minY + (Double(y) / 65535) * max(bounds.height - 1, 0)
        )
    }

    public mutating func interpret(_ input: InputMessage) -> [SyntheticPointerEvent] {
        switch input.kind {
        case .stylus, .mouse: interpretPen(input)
        default: interpretTouch(input)
        }
    }

    /// Ends whatever is in progress, e.g. when the receiver goes away mid-gesture: afterwards no
    /// button is held and no scroll is open.
    public mutating func reset() -> [SyntheticPointerEvent] {
        releaseAll() + releasePen() + leaveProximity()
    }

    // MARK: Touch

    private mutating func interpretTouch(_ input: InputMessage) -> [SyntheticPointerEvent] {
        let points = input.pointers.map { point(x: $0.x, y: $0.y) }
        guard let first = points.first else { return releaseAll() }
        let centroid = CGPoint(x: points.map(\.x).reduce(0, +) / Double(points.count), y: points.map(\.y).reduce(0, +) / Double(points.count))

        switch (input.action, touch) {
        case (.down, _):
            let released = stopMomentum(at: input.eventTimeUs) + releaseAll()  // a gesture whose end never arrived
            touch = .pending(start: first, startTime: input.eventTimeUs)
            return touchMode == .gestures ? released : released + [.move(first, pen: nil)]

        case (.pointerDown, .pending), (.pointerDown, .idle):
            touch = .scrolling(centroid: centroid)
            scrollSamples = []
            return [.scroll(dx: 0, dy: 0, phase: .began)]
        case (.pointerDown, .dragging(let last)):
            touch = .scrolling(centroid: centroid)
            scrollSamples = []
            return [.up(.left, last, pen: nil), .scroll(dx: 0, dy: 0, phase: .began)]

        case (.move, .pending(let start, _)):
            guard touchMode == .pointer, distance(start, first) > touchSlop else { return [] }
            touch = .dragging(last: first)
            return [.down(.left, start, pen: nil), .drag(.left, first, pen: nil)]
        case (.move, .dragging):
            touch = .dragging(last: first)
            return [.drag(.left, first, pen: nil)]
        case (.move, .scrolling(let previous)):
            guard points.count >= 2 else { return [] }
            touch = .scrolling(centroid: centroid)
            let (dx, dy) = (centroid.x - previous.x, centroid.y - previous.y)
            scrollSamples.append((input.eventTimeUs, dx, dy))
            scrollSamples.removeAll { input.eventTimeUs &- $0.time > 100_000 }
            return [.scroll(dx: dx, dy: dy, phase: .changed)]

        case (.up, .pending(let start, let startTime)):
            touch = .idle
            guard touchMode == .pointer else { return [] }
            let button: SyntheticPointerEvent.Button = input.eventTimeUs &- startTime >= longPressMicros ? .right : .left
            return [.down(button, start, pen: nil), .up(button, start, pen: nil)]
        case (.up, .dragging):
            touch = .idle
            return [.up(.left, first, pen: nil)]
        case (.up, .scrolling), (.pointerUp, .scrolling):
            // Scrolling ends when fewer than two fingers remain.
            if input.action == .pointerUp, points.count > 2 { return [] }
            touch = .idle
            return [.scroll(dx: 0, dy: 0, phase: .ended)] + momentum(releasedAt: input.eventTimeUs)

        case (.cancel, _):
            return releaseAll()
        default:
            return []
        }
    }

    /// Inertia after a flick: the velocity over the last 100 ms of movement, if the fingers were
    /// still moving when they left (a pause before lifting means no inertia).
    private mutating func momentum(releasedAt time: UInt64) -> [SyntheticPointerEvent] {
        defer { scrollSamples = [] }
        let recent = scrollSamples.filter { time &- $0.time <= 100_000 }
        guard let oldest = recent.first, recent.count >= 2 else { return [] }
        let seconds = max(Double(time &- oldest.time) / 1_000_000, 0.016)
        let vx = recent.map(\.dx).reduce(0, +) / seconds
        let vy = recent.map(\.dy).reduce(0, +) / seconds
        guard (vx * vx + vy * vy).squareRoot() >= momentumThreshold else { return [] }
        momentumUntil = time &+ 2_000_000
        return [.momentum(vx: vx, vy: vy)]
    }

    private mutating func stopMomentum(at time: UInt64) -> [SyntheticPointerEvent] {
        guard time < momentumUntil else { return [] }
        momentumUntil = 0
        return [.stopMomentum]
    }

    private mutating func releaseAll() -> [SyntheticPointerEvent] {
        defer { touch = .idle }
        switch touch {
        case .dragging(let last): return [.up(.left, last, pen: nil)]
        case .scrolling: return [.scroll(dx: 0, dy: 0, phase: .ended)]
        default: return []
        }
    }

    // MARK: Pen / mouse

    /// S Pen (and a mouse on the tablet). The pen behaves like a pen tablet, as Sidecar makes the
    /// Apple Pencil do: proximity events announce it, and every event, hovering included, carries
    /// pressure and tilt, so drawing apps treat it as a stylus. A mouse stays a plain mouse.
    private mutating func interpretPen(_ input: InputMessage) -> [SyntheticPointerEvent] {
        guard let pointer = input.pointers.first else { return [] }
        let location = point(x: pointer.x, y: pointer.y)
        let isStylus = input.kind == .stylus
        let eraser = pointer.toolType == .eraser
        let pen: SyntheticPointerEvent.Pen? = isStylus ? SyntheticPointerEvent.Pen(
            pressure: input.action.isHover ? 0 : Double(pointer.pressure) / 65535,
            tiltX: Double(pointer.tiltX) / 32767,
            tiltY: Double(pointer.tiltY) / 32767,
            isEraser: eraser
        ) : nil
        defer { penLocation = location }
        if input.action == .hoverExit { return isStylus ? leaveProximity() : [] }
        // In range first (a down without a hover-enter, or the pen flipped to its eraser).
        var events: [SyntheticPointerEvent] = []
        if isStylus, penProximity != eraser {
            events += leaveProximity()
            penProximity = eraser
            events.append(.penProximity(entering: true, eraser: eraser))
        }
        switch input.action {
        case .hoverEnter, .hoverMove:
            events.append(.move(location, pen: pen))
        case .down:
            events += releasePen()  // a stroke whose end never arrived
            let button: SyntheticPointerEvent.Button = pointer.buttons.contains(.stylusPrimary) || pointer.buttons.contains(.secondary) ? .right : .left
            penButton = button
            events.append(.down(button, location, pen: pen))
        case .move:
            if let button = penButton {
                events.append(.drag(button, location, pen: pen))
            } else {
                events.append(.move(location, pen: pen))
            }
        case .up, .cancel:
            let button = penButton ?? .left
            penButton = nil
            events.append(.up(button, location, pen: pen))
        default:
            break
        }
        return events
    }

    private mutating func leaveProximity() -> [SyntheticPointerEvent] {
        guard let eraser = penProximity else { return [] }
        penProximity = nil
        return [.penProximity(entering: false, eraser: eraser)]
    }

    private mutating func releasePen() -> [SyntheticPointerEvent] {
        defer { penButton = nil }
        guard let button = penButton, let penLocation else { return [] }
        return [.up(button, penLocation, pen: nil)]
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
}

extension InputAction {
    var isHover: Bool { self == .hoverEnter || self == .hoverMove || self == .hoverExit }
}
