import AppKit
import Tab2MacCore

/// Follows the Mac's pointer for receivers that draw it themselves (PROTOCOL.md §3.3b), so the
/// pointer can stay out of the video: moving it over a still screen then costs a small message
/// instead of a captured, encoded and decoded frame.
///
/// Event-driven: mouse-move monitors, nothing polls. The shape is read at most every 100 ms
/// while the pointer moves (rendering it to PNG is the only real work here).
@MainActor
public final class CursorTracker {
    public struct Shape: Sendable, Hashable {
        /// Stable for the same image and hotspot within this process; never 0.
        public let id: UInt32
        /// Image size and hotspot in pixels at the tracker's scale.
        public let width: Int
        public let height: Int
        public let hotspotX: Int
        public let hotspotY: Int
        public let png: Data

        public init(id: UInt32, width: Int, height: Int, hotspotX: Int, hotspotY: Int, png: Data) {
            self.id = id
            self.width = width
            self.height = height
            self.hotspotX = hotspotX
            self.hotspotY = hotspotY
            self.png = png
        }
    }

    public struct Sample: Sendable {
        /// Global position in points, top-left origin (CoreGraphics coordinates).
        public let location: CGPoint
        public let shape: Shape?
    }

    /// Pixels per point for shape images (the stream's scale).
    public var scale: CGFloat
    private let onSample: @MainActor (Sample) -> Void
    private var monitors: [Any] = []
    private var shape: Shape?
    private var lastShapeCheck: MediaTime?
    private static let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

    public init(scale: CGFloat, onSample: @escaping @MainActor (Sample) -> Void) {
        self.scale = scale
        self.onSample = onSample
    }

    public var isRunning: Bool { !monitors.isEmpty }

    /// Whether the system reports the current pointer image (else the pointer stays in the video).
    public static var isSupported: Bool { NSCursor.currentSystem != nil }

    public func start() {
        guard monitors.isEmpty else { return }
        // Other apps' events (global) and ours (local, e.g. over the test pattern window).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: Self.events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.moved(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: Self.events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.moved(event) }
            return event
        }) { monitors.append(local) }
        lastShapeCheck = nil
        Log.session.info("cursor.tracking monitors=\(self.monitors.count) supported=\(Self.isSupported)")
        if let location = CGEvent(source: nil)?.location { report(location) }
    }

    public func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func moved(_ event: NSEvent) {
        guard let location = event.cgEvent?.location else { return }
        report(location)
    }

    private func report(_ location: CGPoint) {
        let now = MediaTime.now()
        if lastShapeCheck.map({ now - $0 >= .milliseconds(100) }) ?? true {
            lastShapeCheck = now
            if let current = Self.currentShape(scale: scale) { shape = current }
        }
        onSample(Sample(location: location, shape: shape))
    }

    /// The pointer image as the display shows it, rendered at `scale`.
    static func currentShape(scale: CGFloat) -> Shape? {
        guard let cursor = NSCursor.currentSystem else { return nil }
        let image = cursor.image
        let width = max(1, Int((image.size.width * scale).rounded(.up)))
        let height = max(1, Int((image.size.height * scale).rounded(.up)))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let hotspotX = Int((cursor.hotSpot.x * scale).rounded())
        let hotspotY = Int((cursor.hotSpot.y * scale).rounded())
        var hasher = Hasher()
        hasher.combine(png)
        hasher.combine(hotspotX)
        hasher.combine(hotspotY)
        let id = UInt32(truncatingIfNeeded: hasher.finalize()) | 1  // odd, so never 0
        return Shape(id: id, width: width, height: height, hotspotX: hotspotX, hotspotY: hotspotY, png: png)
    }
}
