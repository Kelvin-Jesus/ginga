import AppKit
import CoreGraphics
import DisplayCapture
import Foundation
import os
import Tab2MacCore
import VirtualDisplay

public struct VerificationStep: Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case passed, failed, skipped
    }

    public var id: String
    public var title: String
    public var outcome: Outcome
    public var detail: String
    public var milliseconds: Double
}

public struct VerificationReport: Codable, Sendable {
    public var tool = "Tab2Mac milestone-1 verification"
    public var date: Date
    public var host: HostInfo
    public var backend: String
    public var displayID: UInt32?
    public var steps: [VerificationStep] = []
    public var capture: CaptureStatisticsSnapshot?
    public var snapshotPath: String?

    public var passed: Bool { !steps.contains { $0.outcome == .failed } }

    public var summary: String {
        var lines = ["Tab2Mac M1 verification — \(host.model), macOS \(host.macOSVersion)", "backend: \(backend)"]
        for step in steps {
            let mark = switch step.outcome {
            case .passed: "PASS"
            case .failed: "FAIL"
            case .skipped: "SKIP"
            }
            lines.append("[\(mark)] \(step.title) — \(step.detail)")
        }
        if let snapshotPath { lines.append("snapshot: \(snapshotPath)") }
        lines.append(passed ? "RESULT: PASSED" : "RESULT: FAILED")
        return lines.joined(separator: "\n")
    }
}

/// Runs the milestone-1 acceptance checks against the real system:
/// MacBook display + an independently addressable virtual display + windows movable between them,
/// then capture of that display only.
@MainActor
public final class M1Verifier {
    public struct Options: Sendable {
        public var configuration: VirtualDisplayConfiguration
        public var captureSettings: CaptureSettings
        public var includeCapture: Bool
        public var captureSeconds: Double
        public var exerciseLiveChanges: Bool
        public var snapshotURL: URL?

        public init(
            configuration: VirtualDisplayConfiguration,
            captureSettings: CaptureSettings = CaptureSettings(),
            includeCapture: Bool = true,
            captureSeconds: Double = 2,
            exerciseLiveChanges: Bool = true,
            snapshotURL: URL? = nil
        ) {
            self.configuration = configuration
            self.captureSettings = captureSettings
            self.includeCapture = includeCapture
            self.captureSeconds = captureSeconds
            self.exerciseLiveChanges = exerciseLiveChanges
            self.snapshotURL = snapshotURL
        }
    }

    private let provider: VirtualDisplayProvider
    private let capture: (any DisplayCaptureSource)?
    private let displays = CoreGraphicsDisplayServices()
    private var report: VerificationReport

    /// The provider must not be shared with a running `DisplaySession`.
    public init(provider: VirtualDisplayProvider, capture: (any DisplayCaptureSource)?) {
        self.provider = provider
        self.capture = capture
        self.report = VerificationReport(date: Date(), host: .current(), backend: provider.backendIdentifier)
    }

    public func run(_ options: Options) async -> VerificationReport {
        report = VerificationReport(date: Date(), host: .current(), backend: provider.backendIdentifier)

        let availability = provider.backendAvailability()
        record("backend-available", "Virtual display backend is available", availability.isAvailable ? .passed : .failed, availability.summary, 0)
        guard availability.isAvailable else { return report }

        let started = MediaTime.now()
        let active: ActiveVirtualDisplay
        do {
            active = try await provider.start(options.configuration)
        } catch {
            record("display-created", "Virtual display is created", .failed, error.description, elapsed(since: started))
            return report
        }
        report.displayID = active.displayID
        record("display-created", "Virtual display is created", .passed, "display \(active.displayID) \"\(options.configuration.name)\"", elapsed(since: started))

        await checkIndependentDisplay(active)
        await checkAppKitScreen(active, name: options.configuration.name)
        await checkSystemInformation(name: options.configuration.name)
        checkTargetMode(active)
        await checkWindowMovement(to: active.displayID)
        if options.exerciseLiveChanges {
            await checkLiveModeChange(active, options: options)
            await checkLiveOrientationChange(active, options: options)
        }
        await checkCapture(options: options)

        let stopStarted = MediaTime.now()
        await provider.stop()
        let removed = await poll(timeout: 3) { !self.displays.onlineDisplayIDs().contains(active.displayID) }
        record("display-removed", "Virtual display is removed on stop", removed ? .passed : .failed,
               removed ? "display \(active.displayID) is offline" : "display \(active.displayID) still online", elapsed(since: stopStarted))
        Log.session.info("verify.finished passed=\(self.report.passed)")
        return report
    }

    // MARK: Checks

    private func checkIndependentDisplay(_ active: ActiveVirtualDisplay) async {
        let id = active.displayID
        let online = displays.onlineDisplayIDs()
        let activeIDs = DisplayInspection.activeDisplayIDs()
        let passed = id != 0 && id != CGMainDisplayID() && CGDisplayIsBuiltin(id) == 0
            && online.contains(id) && activeIDs.contains(id) && online.count >= 2
        record("independent-display-id", "Has its own CGDirectDisplayID next to the built-in display",
               passed ? .passed : .failed,
               "id=\(id) main=\(CGMainDisplayID()) online=\(online) active=\(activeIDs) builtin=\(CGDisplayIsBuiltin(id) != 0)", 0)

        let mirrored = CGDisplayIsInMirrorSet(id) != 0
        let bounds = CGDisplayBounds(id)
        record("extends-desktop", "Extends the desktop (not mirroring)", !mirrored && active.isExtendingDesktop ? .passed : .failed,
               "bounds=\(describe(bounds)) mainBounds=\(describe(CGDisplayBounds(CGMainDisplayID()))) mirrored=\(mirrored)", 0)
    }

    private func checkAppKitScreen(_ active: ActiveVirtualDisplay, name: String) async {
        let started = MediaTime.now()
        let found = await poll(timeout: 3) { DisplayInspection.screen(for: active.displayID) != nil }
        guard found, let screen = DisplayInspection.screen(for: active.displayID) else {
            record("appkit-screen", "Applications see it as a separate screen (NSScreen)", .failed, "no NSScreen with NSScreenNumber \(active.displayID)", elapsed(since: started))
            return
        }
        let nameMatches = screen.localizedName == name
        record("appkit-screen", "Applications see it as a separate screen (NSScreen)", nameMatches ? .passed : .failed,
               "'\(screen.localizedName)' frame=\(describe(screen.frame)) scale=\(screen.backingScaleFactor) screens=\(NSScreen.screens.count)",
               elapsed(since: started))
    }

    private func checkSystemInformation(name: String) async {
        let started = MediaTime.now()
        let names = await DisplayInspection.systemProfilerDisplayNames()
        record("system-information", "Listed by System Information (same list as System Settings › Displays)",
               names.contains(name) ? .passed : .failed, "displays: \(names)", elapsed(since: started))
    }

    private func checkTargetMode(_ active: ActiveVirtualDisplay) {
        let matches = active.mode?.matches(active.plan.target) == true
        record("target-mode", "Configured resolution, scaling and refresh rate are active", matches ? .passed : .failed,
               "target=\(active.plan.target) actual=\(active.mode?.description ?? "none")", 0)
    }

    private func checkWindowMovement(to displayID: CGDirectDisplayID) async {
        let started = MediaTime.now()
        // The MacBook's own panel when present (an external monitor may be the main display).
        let homeID = displays.onlineDisplayIDs().first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
        let title = CGDisplayIsBuiltin(homeID) != 0
            ? "A window moves from the built-in display to the virtual display and back"
            : "A window moves from the main display to the virtual display and back"
        guard let target = DisplayInspection.screen(for: displayID),
              let home = DisplayInspection.screen(for: homeID)
        else {
            record("window-moves", title, .failed, "screens unavailable", 0)
            return
        }
        let size = NSSize(width: 420, height: 260)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Tab2Mac — window move test"
        window.isReleasedWhenClosed = false
        func center(on screen: NSScreen) -> NSPoint {
            NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2)
        }

        window.setFrameOrigin(center(on: home))
        window.orderFrontRegardless()
        await pause(0.3)
        let startScreen = screenNumber(of: window)

        window.setFrameOrigin(center(on: target))
        await pause(0.4)
        let movedScreen = screenNumber(of: window)
        let windowBounds = cgBounds(of: window)
        let insideVirtual = windowBounds.map { CGDisplayBounds(displayID).contains(CGPoint(x: $0.midX, y: $0.midY)) } ?? false

        window.setFrameOrigin(center(on: home))
        await pause(0.3)
        let returnedScreen = screenNumber(of: window)
        window.orderOut(nil)

        let passed = startScreen == homeID && movedScreen == displayID && insideVirtual && returnedScreen == homeID
        record("window-moves", title,
               passed ? .passed : .failed,
               "start=\(startScreen.map(String.init) ?? "nil") moved=\(movedScreen.map(String.init) ?? "nil") (WindowServer bounds \(windowBounds.map(describe) ?? "nil") inside virtual=\(insideVirtual)) back=\(returnedScreen.map(String.init) ?? "nil")",
               elapsed(since: started))
    }

    private func checkLiveModeChange(_ active: ActiveVirtualDisplay, options: Options) async {
        let started = MediaTime.now()
        guard let alternative = options.configuration.extraResolutions.first(where: { $0 != options.configuration.resolution }) else {
            record("live-mode-change", "Resolution/scaling changes apply live", .skipped, "no alternative resolution configured", 0)
            return
        }
        var changed = options.configuration
        changed.resolution = alternative
        do {
            let result = try await provider.apply(changed)
            let ok = result.displayID == active.displayID && result.mode?.matches(result.plan.target) == true
            _ = try await provider.apply(options.configuration)
            record("live-mode-change", "Resolution/scaling changes apply live", ok ? .passed : .failed,
                   "switched to \(result.mode?.description ?? "none") on display \(result.displayID) and back", elapsed(since: started))
        } catch {
            record("live-mode-change", "Resolution/scaling changes apply live", .failed, String(describing: error), elapsed(since: started))
        }
    }

    private func checkLiveOrientationChange(_ active: ActiveVirtualDisplay, options: Options) async {
        let started = MediaTime.now()
        var rotated = options.configuration
        rotated.orientation = options.configuration.orientation == .landscape ? .portrait : .landscape
        do {
            let result = try await provider.apply(rotated)
            let isRotated = (result.bounds.height > result.bounds.width) == (rotated.orientation == .portrait)
            let ok = result.displayID == active.displayID && isRotated && result.mode?.matches(result.plan.target) == true
            _ = try await provider.apply(options.configuration)
            record("live-orientation-change", "Orientation changes apply live on the same display", ok ? .passed : .failed,
                   "\(rotated.orientation.rawValue): \(result.mode?.description ?? "none"), bounds=\(describe(result.bounds))", elapsed(since: started))
        } catch {
            record("live-orientation-change", "Orientation changes apply live on the same display", .failed, String(describing: error), elapsed(since: started))
        }
    }

    private func checkCapture(options: Options) async {
        let title = "Frames are captured from the virtual display only"
        guard options.includeCapture else {
            record("capture", title, .skipped, "capture disabled for this run", 0)
            return
        }
        guard let capture else {
            record("capture", title, .skipped, "no capture source", 0)
            return
        }
        guard ScreenCapturePermission.isGranted else {
            record("capture", title, .skipped,
                   "Screen Recording permission not granted to this process — System Settings › Privacy & Security › Screen & System Audio Recording", 0)
            return
        }
        guard let active = provider.activeDisplay else {
            record("capture", title, .failed, "display is no longer active", 0)
            return
        }

        let started = MediaTime.now()
        let load = LoadGenerator()
        if let screen = await DisplayInspection.waitForScreen(active.displayID) {
            load.start(on: screen, title: "Tab2Mac capture test")
        }
        let lastFrame = LockedValue<CapturedFrame?>(nil)
        let configuration = options.captureSettings.captureConfiguration(for: active)
        do {
            try await capture.start(displayID: active.displayID, configuration: configuration, onFrame: { lastFrame.set($0) }, onStop: { _ in })
        } catch {
            load.stop()
            record("capture", title, .failed, error.description, elapsed(since: started))
            return
        }
        try? await Task.sleep(for: .seconds(options.captureSeconds))
        let statistics = capture.statistics
        if let url = options.snapshotURL, let frame = lastFrame.value {
            do {
                try FrameSnapshot.writePNG(frame.pixelBuffer, to: url)
                report.snapshotPath = url.path
            } catch {
                Log.session.error("verify.snapshot-failed reason=\(String(describing: error), privacy: .public)")
            }
        }
        lastFrame.set(nil)
        await capture.stop()
        load.stop()

        report.capture = statistics
        let expected = CaptureSizing.outputSize(displayPixels: active.pixelSize, maxOutputSize: configuration.maxOutputSize)
        let enoughFrames = statistics.completeFrames >= Int(options.captureSeconds * 10)
        let passed = enoughFrames && statistics.lastPixelSize == expected
        // SCK's displayTime is the vsync the frame targets, so negative = delivered before that vsync.
        let latency = statistics.captureLatencyMilliseconds.map { String(format: "delivery vs display time p50 %.1f ms / p95 %.1f ms", $0.p50, $0.p95) } ?? "delivery timing n/a"
        record("capture", title, passed ? .passed : .failed,
               "\(statistics.completeFrames) frames in \(options.captureSeconds)s (\(String(format: "%.1f", statistics.framesPerSecond)) fps now), \(latency), size \(statistics.lastPixelSize?.description ?? "none") (expected \(expected))",
               elapsed(since: started))
    }

    // MARK: Helpers

    private func record(_ id: String, _ title: String, _ outcome: VerificationStep.Outcome, _ detail: String, _ milliseconds: Double) {
        report.steps.append(VerificationStep(id: id, title: title, outcome: outcome, detail: detail, milliseconds: milliseconds))
        Log.session.info("verify.step id=\(id, privacy: .public) outcome=\(outcome.rawValue, privacy: .public) detail=\(detail, privacy: .public)")
    }

    private func elapsed(since start: MediaTime) -> Double {
        (MediaTime.now() - start).inMilliseconds
    }

    private func poll(timeout seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = MediaTime.now().advanced(by: .milliseconds(Int64(seconds * 1000)))
        while !condition() {
            guard MediaTime.now() < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int64(seconds * 1000)))
    }

    private func screenNumber(of window: NSWindow) -> CGDirectDisplayID? {
        (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// The window's bounds as WindowServer reports them (global, top-left origin).
    private func cgBounds(of window: NSWindow) -> CGRect? {
        guard
            let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(window.windowNumber)) as? [[String: Any]],
            let bounds = info.first?[kCGWindowBounds as String] as? NSDictionary
        else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    private func describe(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height)))"
    }
}

/// A tiny lock-protected box for handing values between the capture queue and the main actor.
public final class LockedValue<Value: Sendable>: @unchecked Sendable {  // `stored` is guarded by `lock`
    private let lock = NSLock()
    private var stored: Value

    public init(_ value: Value) {
        stored = value
    }

    public var value: Value { lock.withLock { stored } }

    public func set(_ value: Value) {
        lock.withLock { stored = value }
    }

    public func update<T>(_ body: (inout Value) -> T) -> T {
        lock.withLock { body(&stored) }
    }
}
