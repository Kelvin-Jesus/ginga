import CoreGraphics
import DisplayCapture
import Foundation
import os
import Tab2MacCore
import VirtualDisplay

/// Distributes captured frames to any number of consumers (preview, encoder, benchmarks).
/// Sinks run on the capture queue and must return quickly.
public final class FrameSinkRegistry: Sendable {
    public struct Token: Hashable, Sendable {
        fileprivate let id: UInt64
    }

    private let sinks = OSAllocatedUnfairLock(initialState: (next: UInt64(0), handlers: [UInt64: @Sendable (CapturedFrame) -> Void]()))
    private let last = OSAllocatedUnfairLock<CapturedFrame?>(initialState: nil)

    public init() {}

    @discardableResult
    public func add(_ sink: @escaping @Sendable (CapturedFrame) -> Void) -> Token {
        sinks.withLock { state in
            state.next += 1
            state.handlers[state.next] = sink
            return Token(id: state.next)
        }
    }

    public func remove(_ token: Token) {
        sinks.withLock { _ = $0.handlers.removeValue(forKey: token.id) }
    }

    public var count: Int { sinks.withLock { $0.handlers.count } }

    /// The most recent frame while capture runs: a static screen produces no new frames, so a
    /// new receiver or a keyframe request starts from this one.
    public var latest: CapturedFrame? { last.withLock { $0 } }

    public func clearLatest() {
        last.withLock { $0 = nil }
    }

    public func deliver(_ frame: CapturedFrame) {
        last.withLock { $0 = frame }
        let handlers = sinks.withLock { Array($0.handlers.values) }
        for handler in handlers { handler(frame) }
    }
}

public struct SessionTiming: Sendable {
    public var initialRetryDelay: Duration
    public var maximumRetryDelay: Duration

    public init(initialRetryDelay: Duration = .milliseconds(500), maximumRetryDelay: Duration = .seconds(5)) {
        self.initialRetryDelay = initialRetryDelay
        self.maximumRetryDelay = maximumRetryDelay
    }

    func retryDelay(attempt: Int) -> Duration {
        var delay = initialRetryDelay
        for _ in 1..<max(attempt, 1) where delay < maximumRetryDelay { delay *= 2 }
        return min(delay, maximumRetryDelay)
    }
}

/// Wires Layer 1 (virtual display) to Layer 2 (capture) — and later to encoding and transport.
///
/// The display's lifetime is owned by the provider and never depends on capture: capture follows
/// the display (start on activation, restart on any reconfiguration, stop on removal) and retries
/// on its own when the stream ends (screen lock, sleep).
@MainActor
public final class DisplaySession {
    public enum CaptureState: Equatable, Sendable {
        case idle
        case starting
        case running(displayID: CGDirectDisplayID)
        /// Screen Recording permission is missing; the user has to grant it.
        case waitingForPermission
        case retrying(attempt: Int, reason: String)
        case failed(String)
    }

    public let provider: VirtualDisplayProvider
    public let frames = FrameSinkRegistry()
    public private(set) var configuration: Tab2MacConfiguration
    public private(set) var captureState: CaptureState = .idle {
        didSet { if captureState != oldValue { notifyChange() } }
    }
    /// Whether frames are captured while the display is active (the display exists either way).
    public private(set) var isCaptureEnabled: Bool
    /// Who needs frames. Capture runs only while someone does: nothing is captured, converted or
    /// woken up for when no tablet (or preview) is watching.
    public enum CaptureConsumer: Hashable, Sendable {
        case stream, preview, always
    }
    private var captureDemand: Set<CaptureConsumer>
    /// UI hook: called on the main actor after any state change.
    public var onChange: (@MainActor () -> Void)?
    /// Display events, forwarded after the session reacted to them.
    public var onDisplayEvent: (@MainActor (VirtualDisplayEvent) -> Void)?

    private let capture: any DisplayCaptureSource
    private let timing: SessionTiming
    /// The capture source's operations run one at a time: every start or stop is a task that first
    /// waits for the previous one, so two starts can never overlap (and orphan a stream).
    private var captureTask: Task<Void, Never>?
    private var captureGeneration = 0
    /// What the running (or starting) capture was started for; a reconfiguration that changes none
    /// of it (e.g. the display only moved) doesn't restart capture.
    private var captureKey: CaptureKey?
    /// Consecutive stops soon after starting (e.g. the lock screen): restarts back off.
    private var stopStreak = 0
    private var captureRunningSince: MediaTime?

    private struct CaptureKey: Equatable {
        var displayID: CGDirectDisplayID
        var pixelSize: PixelSize
        var refreshRate: Double?
        var configuration: CaptureConfiguration
    }

    public init(
        provider: VirtualDisplayProvider,
        capture: any DisplayCaptureSource,
        configuration: Tab2MacConfiguration,
        captureEnabled: Bool = true,
        timing: SessionTiming = SessionTiming()
    ) {
        self.provider = provider
        self.capture = capture
        self.configuration = configuration
        self.isCaptureEnabled = captureEnabled
        self.captureDemand = captureEnabled ? [.always] : []
        self.timing = timing
        provider.onEvent = { [weak self] event in self?.handle(event) }
    }

    public var activeDisplay: ActiveVirtualDisplay? { provider.activeDisplay }

    /// Whether the Mac runs on battery (the app reports IOKit power-source changes).
    public private(set) var isOnBattery = false

    /// The display configuration in effect: `configuration.display`, slowed down on battery
    /// when `PowerSettings.batteryRefreshRate` says so.
    public var effectiveDisplay: VirtualDisplayConfiguration {
        let configured = configuration.effectiveDisplay(onBattery: isOnBattery)
        guard var tablet = tabletDisplay else { return configured }
        // The tablet's panel and identity; the user's orientation, placement and rate (capped).
        tablet.orientation = configured.orientation
        tablet.arrangement = configured.arrangement
        tablet.hiDPI = configured.hiDPI
        tablet.refreshRate = min(configured.refreshRate, tablet.panel.maxRefreshRate)
        return tablet
    }

    /// While a display created for a tablet exists: that tablet's panel (another device than the
    /// configured one), from `ensureDisplay(owner:tabletDisplay:)`.
    public private(set) var tabletDisplay: VirtualDisplayConfiguration?

    /// Switches the live display's refresh rate when the power source changes (a live mode change
    /// on the same display; capture restarts and the stream follows).
    public func setOnBattery(_ onBattery: Bool) async {
        guard onBattery != isOnBattery else { return }
        isOnBattery = onBattery
        notifyChange()
        await serialized {
            // Read when the operation runs: an earlier one may have changed the display meanwhile.
            guard let active = self.provider.activeDisplay, active.configuration != self.effectiveDisplay else { return }
            do {
                try await self.provider.apply(self.effectiveDisplay)
                Log.session.info("session.power-refresh on_battery=\(onBattery) hz=\(self.effectiveDisplay.refreshRate)")
            } catch {
                Log.session.error("session.power-refresh-failed reason=\(String(describing: error), privacy: .public)")
            }
        }
    }
    public var captureStatistics: CaptureStatisticsSnapshot { capture.statistics }

    // MARK: Display lifecycle

    /// Who asked for the display: a tablet's display goes away with the tablet (after
    /// `streaming.displayLingerSeconds`); one the user created stays. Kept across recreations
    /// (configuration changes), cleared when the display is removed or lost.
    public enum DisplayOwner: Sendable, Equatable {
        case user, stream
    }

    public private(set) var displayOwner: DisplayOwner?

    /// Display operations (start, apply, stop, the power-source switch) run one at a time, in
    /// call order: each waits for the previous one. The provider's steps suspend while
    /// WindowServer catches up, and interleaving them would act on a display that is going away
    /// (e.g. a tablet reconnecting while its old display is being removed).
    private var lastDisplayOperation: Task<Void, Never>?

    private func serialized<T: Sendable>(_ operation: @escaping @MainActor () async -> T) async -> T {
        let previous = lastDisplayOperation
        // Unstructured on purpose: a caller that gets cancelled must not leave an operation half done.
        let task = Task { @MainActor in
            await previous?.value
            return await operation()
        }
        lastDisplayOperation = Task { _ = await task.value }
        return await task.value
    }

    /// Creates the display. Fails with `.alreadyActive` if there is one.
    @discardableResult
    public func startDisplay(owner: DisplayOwner = .user) async throws(VirtualDisplayError) -> ActiveVirtualDisplay {
        try await serialized {
            self.tabletDisplay = nil  // the user's display is the configured one
            return await self.start(owner: owner)
        }.get()
    }

    /// The display, created for `owner` unless one exists. In operation order: a removal already
    /// under way completes first, and a fresh display replaces it.
    @discardableResult
    /// - Parameter tabletDisplay: when a display gets created, shape it for this device instead
    ///   of the configured one (see `effectiveDisplay`).
    public func ensureDisplay(owner: DisplayOwner, tabletDisplay: VirtualDisplayConfiguration? = nil) async throws(VirtualDisplayError) -> ActiveVirtualDisplay {
        try await serialized { () -> Result<ActiveVirtualDisplay, VirtualDisplayError> in
            if let active = self.provider.activeDisplay { return .success(active) }
            self.tabletDisplay = tabletDisplay
            let result = await self.start(owner: owner)
            if case .failure = result { self.tabletDisplay = nil }
            return result
        }.get()
    }

    private func start(owner: DisplayOwner) async -> Result<ActiveVirtualDisplay, VirtualDisplayError> {
        do throws(VirtualDisplayError) {
            let active = try await provider.start(effectiveDisplay)
            displayOwner = owner
            return .success(active)
        } catch {
            return .failure(error)
        }
    }

    public func stopDisplay() async {
        await serialized {
            self.displayOwner = nil
            self.tabletDisplay = nil
            await self.provider.stop()
        }
    }

    /// Applies a new configuration; the display is reconfigured live when possible. Capture is
    /// restarted by the resulting `.reconfigured` event, which also picks up new capture settings.
    /// If the display can't follow, the previous configuration is restored (unless another one
    /// was applied meanwhile) and the error is thrown.
    @discardableResult
    public func apply(_ configuration: Tab2MacConfiguration) async throws -> ActiveVirtualDisplay? {
        try configuration.validate()
        let previous = self.configuration
        self.configuration = configuration
        notifyChange()
        let result = await serialized { () -> Result<ActiveVirtualDisplay?, VirtualDisplayError> in
            guard self.provider.activeDisplay != nil else { return .success(nil) }
            do throws(VirtualDisplayError) {
                return .success(try await self.provider.apply(self.effectiveDisplay))
            } catch {
                return .failure(error)
            }
        }
        if case .failure = result, self.configuration == configuration {
            self.configuration = previous
            notifyChange()
        }
        return try result.get()
    }

    /// Whether the pointer is drawn into captured frames (with `capture.showsCursor`). Off while
    /// every receiver draws the pointer itself (PROTOCOL.md §3.3b).
    public private(set) var cursorInCapture = true

    public func setCursorInCapture(_ shown: Bool) {
        guard shown != cursorInCapture else { return }
        cursorInCapture = shown
        // A different capture configuration: restart capture, as for any reconfiguration.
        if isCaptureEnabled, let active = provider.activeDisplay, key(for: active) != captureKey { startCapture(for: active) }
    }

    private func captureConfiguration(for active: ActiveVirtualDisplay) -> CaptureConfiguration {
        var capture = configuration.capture.captureConfiguration(for: active)
        capture.showsCursor = capture.showsCursor && cursorInCapture
        return capture
    }

    /// Registers or withdraws a consumer's need for frames.
    public func setCaptureDemand(_ consumer: CaptureConsumer, _ wanted: Bool) async {
        if wanted { captureDemand.insert(consumer) } else { captureDemand.remove(consumer) }
        await updateCapture(enabled: !captureDemand.isEmpty)
    }

    /// Unconditional on/off (headless modes and tests); same as the `.always` consumer.
    public func setCaptureEnabled(_ enabled: Bool) async {
        await setCaptureDemand(.always, enabled)
    }

    private func updateCapture(enabled: Bool) async {
        guard enabled != isCaptureEnabled else { return }
        isCaptureEnabled = enabled
        if enabled, let active = provider.activeDisplay {
            startCapture(for: active)
        } else if !enabled {
            await enqueueStop().value
        }
        notifyChange()
    }

    /// Retry capture now (e.g. after the user granted Screen Recording permission).
    public func retryCapture() {
        guard isCaptureEnabled, let active = provider.activeDisplay else { return }
        startCapture(for: active)
    }

    // MARK: Event handling

    private func handle(_ event: VirtualDisplayEvent) {
        switch event {
        case .activated(let active), .reconfigured(let active):
            // Restart when what is captured changed: ScreenCaptureKit can keep capturing a stale
            // display after a reconfiguration (FB17797423), and the pixel size may change. A pure
            // move (arrangement) changes none of that, and a restart would be a visible hiccup.
            if isCaptureEnabled, key(for: active) != captureKey { startCapture(for: active) }
        case .deactivated:
            enqueueStop()
        case .lost:
            displayOwner = nil
            tabletDisplay = nil
            enqueueStop()
        }
        notifyChange()
        onDisplayEvent?(event)
    }

    private func key(for active: ActiveVirtualDisplay) -> CaptureKey {
        CaptureKey(
            displayID: active.displayID, pixelSize: active.pixelSize, refreshRate: active.mode?.refreshRate,
            configuration: captureConfiguration(for: active)
        )
    }

    private func startCapture(for active: ActiveVirtualDisplay, initialDelay: Duration = .zero) {
        let previous = captureTask
        previous?.cancel()
        captureGeneration += 1
        let generation = captureGeneration
        captureKey = key(for: active)
        frames.clearLatest()  // a frame of the old configuration must not be re-encoded as a keyframe
        if initialDelay == .zero { captureState = .starting }
        captureTask = Task { [weak self] in
            await previous?.value
            if initialDelay > .zero { try? await Task.sleep(for: initialDelay) }
            await self?.runCapture(for: active, generation: generation)
        }
    }

    /// Queues a stop behind any start in flight (which stops what it started once superseded).
    @discardableResult
    private func enqueueStop() -> Task<Void, Never> {
        let previous = captureTask
        previous?.cancel()
        captureGeneration += 1
        captureKey = nil
        captureRunningSince = nil
        captureState = .idle
        let capture = capture
        let frames = frames
        let task = Task {
            await previous?.value
            await capture.stop()
            frames.clearLatest()
        }
        captureTask = task
        return task
    }

    private func runCapture(for active: ActiveVirtualDisplay, generation: Int) async {
        await capture.stop()
        var attempt = 0
        while !Task.isCancelled, generation == captureGeneration {
            let configuration = captureConfiguration(for: active)
            let frames = frames
            do {
                try await capture.start(
                    displayID: active.displayID,
                    configuration: configuration,
                    onFrame: { frames.deliver($0) },
                    onStop: { [weak self] error in
                        Task { @MainActor in self?.captureStopped(error, generation: generation) }
                    }
                )
                guard !Task.isCancelled, generation == captureGeneration else {
                    await capture.stop()
                    return
                }
                captureState = .running(displayID: active.displayID)
                captureRunningSince = .now()
                Log.session.info("session.capture-running display=\(active.displayID) attempt=\(attempt + 1)")
                return
            } catch .permissionDenied {
                captureState = .waitingForPermission
                Log.session.error("session.capture-permission-missing display=\(active.displayID)")
                return
            } catch .cancelled {
                return
            } catch {
                attempt += 1
                captureState = .retrying(attempt: attempt, reason: error.description)
                Log.session.error("session.capture-retry display=\(active.displayID) attempt=\(attempt) reason=\(error.description, privacy: .public)")
                try? await Task.sleep(for: timing.retryDelay(attempt: attempt))
            }
        }
    }

    private func captureStopped(_ error: CaptureError, generation: Int) {
        guard generation == captureGeneration else { return }
        guard isCaptureEnabled, let active = provider.activeDisplay else {
            captureState = .idle
            return
        }
        // Typically -3808 (display asleep / screen locked): keep retrying until it comes back,
        // backing off while it keeps stopping right after starting.
        let ranBriefly = captureRunningSince.map { MediaTime.now() - $0 < .seconds(10) } ?? true
        stopStreak = ranBriefly ? stopStreak + 1 : 1
        captureRunningSince = nil
        captureState = .retrying(attempt: stopStreak, reason: error.description)
        startCapture(for: active, initialDelay: timing.retryDelay(attempt: stopStreak))
    }

    private func notifyChange() {
        onChange?()
    }
}
