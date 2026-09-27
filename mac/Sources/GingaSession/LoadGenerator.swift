import AppKit
import QuartzCore

/// A window that animates continuously, so WindowServer composes a new frame on every refresh.
///
/// ScreenCaptureKit only delivers frames when content changes; benchmarks and self-tests put
/// this on the virtual display to measure capture at full rate. The animation runs in the
/// render server (Core Animation), so it costs this process almost nothing.
@MainActor
public final class LoadGenerator {
    private var window: NSWindow?
    private var clockTimer: Timer?
    private var clockLayer: CATextLayer?
    private let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    public init() {}

    public var isRunning: Bool { window != nil }

    /// The screen the window is on now (macOS moves windows when displays reconfigure).
    public var screen: NSScreen? { window?.screen }

    public func start(on screen: NSScreen, title: String = "Ginga load generator") {
        stop()
        let frame = screen.visibleFrame.insetBy(dx: screen.visibleFrame.width * 0.1, dy: screen.visibleFrame.height * 0.1)
        // Place by global frame: with `screen:`, NSWindow reads the content rect relative to that
        // screen's origin, which put the window on another display whenever the virtual display
        // wasn't at the origin.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: frame.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.setFrame(window.frameRect(forContentRect: frame), display: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1).cgColor

        let bar = CALayer()
        bar.backgroundColor = NSColor.systemTeal.cgColor
        bar.frame = CGRect(x: 0, y: 0, width: 80, height: frame.height)
        content.layer?.addSublayer(bar)

        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = 40
        sweep.toValue = frame.width - 40
        sweep.duration = 1.5
        sweep.autoreverses = true
        sweep.repeatCount = .infinity
        // Without an explicit range Core Animation may run this at 60 fps (e.g. for an inactive
        // app). Ask for more than any display offers, not this screen's current maximum: Core
        // Animation clamps to the display, and a live 60 → 120 Hz switch (power adapter plugged
        // in) must not leave the pattern at 60.
        sweep.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 240, preferred: 240)
        bar.add(sweep, forKey: "sweep")

        let clock = CATextLayer()
        clock.fontSize = 64
        clock.foregroundColor = NSColor.white.cgColor
        clock.alignmentMode = .center
        clock.contentsScale = screen.backingScaleFactor
        clock.frame = CGRect(x: 0, y: frame.height / 2 - 40, width: frame.width, height: 80)
        content.layer?.addSublayer(clock)

        window.contentView = content
        window.orderFrontRegardless()
        self.window = window
        clockLayer = clock

        clockTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clockLayer?.string = clockFormatter.string(from: Date())
        CATransaction.commit()
    }

    public func stop() {
        clockTimer?.invalidate()
        clockTimer = nil
        clockLayer = nil
        window?.orderOut(nil)
        window = nil
    }
}
