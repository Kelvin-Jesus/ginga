import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import GingaCore
import Testing
import VirtualDisplay
import VirtualDisplayTestSupport
@testable import DisplayCapture
@testable import GingaSession

/// Records what the session asks of the capture layer and lets tests drive its callbacks.
final class FakeCaptureSource: DisplayCaptureSource, @unchecked Sendable {
    struct Start: Sendable {
        let displayID: CGDirectDisplayID
        let configuration: CaptureConfiguration
    }

    private let lock = NSLock()
    private var recordedStarts: [Start] = []
    private var recordedAttempts = 0
    private var recordedStops = 0
    private var pendingFailures: [CaptureError] = []
    private var onFrame: (@Sendable (CapturedFrame) -> Void)?
    private var onStop: (@Sendable (CaptureError) -> Void)?
    private var delay: Duration = .zero
    private var inFlight = 0
    private var maxInFlight = 0
    private var live = 0
    private var maxLive = 0

    var starts: [Start] { lock.withLock { recordedStarts } }
    /// Starts that were waiting at the same time (the real source finds displays slowly).
    var maxConcurrentStarts: Int { lock.withLock { maxInFlight } }
    /// Streams started and not stopped: more than one would be an orphan nothing can stop.
    var liveStreams: Int { lock.withLock { live } }
    var maxLiveStreams: Int { lock.withLock { maxLive } }

    /// Makes every start wait this long before its stream runs.
    func setStartDelay(_ duration: Duration) {
        lock.withLock { delay = duration }
    }
    var attempts: Int { lock.withLock { recordedAttempts } }
    var stops: Int { lock.withLock { recordedStops } }
    var statistics: CaptureStatisticsSnapshot { CaptureStatisticsSnapshot() }

    func failNextStarts(with errors: [CaptureError]) {
        lock.withLock { pendingFailures = errors }
    }

    func start(
        displayID: CGDirectDisplayID,
        configuration: CaptureConfiguration,
        onFrame: @escaping @Sendable (CapturedFrame) -> Void,
        onStop: @escaping @Sendable (CaptureError) -> Void
    ) async throws(CaptureError) {
        let (failure, wait): (CaptureError?, Duration) = lock.withLock {
            recordedAttempts += 1
            if !pendingFailures.isEmpty { return (pendingFailures.removeFirst(), .zero) }
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            return (nil, delay)
        }
        if let failure { throw failure }
        if wait > .zero { try? await Task.sleep(for: wait) }
        lock.withLock {
            inFlight -= 1
            recordedStarts.append(Start(displayID: displayID, configuration: configuration))
            self.onFrame = onFrame
            self.onStop = onStop
            live += 1
            maxLive = max(maxLive, live)
        }
    }

    func stop() async {
        lock.withLock {
            recordedStops += 1
            onFrame = nil
            onStop = nil
            live = max(0, live - 1)
        }
    }

    func emit(_ frame: CapturedFrame) {
        let handler = lock.withLock { onFrame }
        handler?(frame)
    }

    func simulateUnexpectedStop(_ error: CaptureError) {
        let handler = lock.withLock { onStop }
        handler?(error)
    }
}

func makeFrame(sequence: UInt64 = 1) -> CapturedFrame {
    var pixelBuffer: CVPixelBuffer?
    let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
    CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes, &pixelBuffer)
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer!, formatDescriptionOut: &format)
    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer!, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample)
    return CapturedFrame(
        sequenceNumber: sequence, pixelBuffer: pixelBuffer!, sampleBuffer: sample!,
        pixelSize: PixelSize(width: 64, height: 64), displayTime: .now(), arrivalTime: .now(),
        dirtyRectCount: 1, scaleFactor: 2
    )
}

@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}

@MainActor
@Suite("DisplaySession")
struct DisplaySessionTests {
    let system = FakeDisplayServices()
    let capture = FakeCaptureSource()
    let backend: FakeBackend
    let session: DisplaySession

    init() {
        backend = FakeBackend(system: system)
        let provider = VirtualDisplayProvider(
            backend: backend, displays: system, reconfiguration: FakeReconfigurationSource(),
            timing: ProviderTiming(onlineTimeout: .milliseconds(100), pollInterval: .milliseconds(5), modeEnforcementWindow: .zero)
        )
        session = DisplaySession(
            provider: provider, capture: capture, configuration: GingaConfiguration(),
            timing: SessionTiming(initialRetryDelay: .milliseconds(5), maximumRetryDelay: .milliseconds(20))
        )
    }

    @Test func startingTheDisplayStartsCaptureOfThatDisplay() async throws {
        let active = try await session.startDisplay()
        #expect(await eventually { session.captureState == .running(displayID: active.displayID) })
        let start = try #require(capture.starts.first)
        #expect(start.displayID == 77)
        #expect(start.configuration.frameRate == 60)
        #expect(start.configuration.maxOutputSize == PixelSize(width: 2560, height: 1600))
        #expect(start.configuration.pixelFormat == .yuv420VideoRange)
    }

    /// A configuration the display can't follow is not left in effect.
    @Test func aFailedApplyRestoresThePreviousConfiguration() async throws {
        _ = try await session.startDisplay()
        let before = session.configuration
        var configuration = before
        configuration.display.name = "Renamed"  // a creation-time property: the display is recreated
        backend.createError = .creationFailed("WindowServer said no")
        await #expect(throws: VirtualDisplayError.self) { try await session.apply(configuration) }
        #expect(session.configuration == before)
    }

    /// Operations run in call order: an apply issued while the display is being removed waits for
    /// the removal instead of reconfiguring a display that is going away.
    @Test func displayOperationsDoNotInterleave() async throws {
        _ = try await session.startDisplay()
        backend.removalDelay = .milliseconds(60)
        var portrait = session.configuration
        portrait.display.orientation = .portrait
        let stopping = Task { await session.stopDisplay() }
        #expect(await eventually { backend.destroyCount == 1 })  // the removal is under way
        let applied = try await session.apply(portrait)
        await stopping.value
        #expect(applied == nil)  // nothing to reconfigure once the removal completed
        #expect(session.activeDisplay == nil)
        #expect(session.configuration.display.orientation == .portrait)  // kept for the next start
        let restarted = try await session.startDisplay()
        #expect(restarted.plan.target.size.isPortrait)
    }

    /// A receiver that draws the pointer itself: capture restarts without it, and with it again after.
    @Test func thePointerCanBeLeftOutOfCapture() async throws {
        _ = try await session.startDisplay()
        #expect(await eventually { capture.starts.count == 1 })
        #expect(capture.starts.last?.configuration.showsCursor == true)
        session.setCursorInCapture(false)
        #expect(await eventually { capture.starts.count == 2 })
        #expect(capture.starts.last?.configuration.showsCursor == false)
        session.setCursorInCapture(false)  // no change, no restart
        session.setCursorInCapture(true)
        #expect(await eventually { capture.starts.count == 3 })
        #expect(capture.starts.last?.configuration.showsCursor == true)
    }

    @Test func reconfiguringTheDisplayRestartsCapture() async throws {
        _ = try await session.startDisplay()
        #expect(await eventually { capture.starts.count == 1 })
        var configuration = session.configuration
        configuration.display.orientation = .portrait
        try await session.apply(configuration)
        #expect(await eventually { capture.starts.count == 2 })
        #expect(capture.starts.last?.displayID == 77)
        #expect(capture.stops >= 2)
    }

    @Test func removingTheDisplayStopsCapture() async throws {
        _ = try await session.startDisplay()
        #expect(await eventually { capture.starts.count == 1 })
        let stopsBefore = capture.stops
        await session.stopDisplay()
        #expect(await eventually { session.captureState == .idle && capture.stops > stopsBefore })
    }

    @Test func captureCanBeToggledWithoutTouchingTheDisplay() async throws {
        await session.setCaptureEnabled(false)
        let active = try await session.startDisplay()
        try await Task.sleep(for: .milliseconds(20))
        #expect(capture.starts.isEmpty)

        await session.setCaptureEnabled(true)
        #expect(await eventually { session.captureState == .running(displayID: active.displayID) })
        await session.setCaptureEnabled(false)
        #expect(session.captureState == .idle)
        #expect(session.activeDisplay?.displayID == active.displayID)
    }

    /// 120 Hz on the power adapter, 60 Hz on battery, switched live on the same display.
    @Test func thePowerSourceSwitchesTheLiveRefreshRate() async throws {
        var configuration = session.configuration
        configuration.display.refreshRate = 120
        try await session.apply(configuration)
        let active = try await session.startDisplay()
        #expect(active.mode?.refreshRate == 120)
        await session.setOnBattery(true)
        #expect(session.activeDisplay?.displayID == active.displayID)  // same display, new mode
        #expect(session.activeDisplay?.mode?.refreshRate == 60)
        await session.setOnBattery(false)
        #expect(session.activeDisplay?.mode?.refreshRate == 120)
    }

    /// A tablet held in portrait connects: the display is created and immediately rotated while
    /// the first capture start is still waiting for ScreenCaptureKit. Starts must not overlap, or
    /// a stream is left running that nothing can stop (review finding).
    @Test func overlappingReconfigurationsNeverLeaveTwoStreams() async throws {
        capture.setStartDelay(.milliseconds(40))
        let active = try await session.startDisplay()
        #expect(await eventually { capture.attempts == 1 })  // the first start is in flight…
        var configuration = session.configuration
        configuration.display.orientation = .portrait  // …when the tablet rotates
        try await session.apply(configuration)
        configuration.display.orientation = .landscape
        try await session.apply(configuration)
        // Two or three starts depending on timing (the second rotation may supersede the first
        // restart or follow it); what matters is that they never overlap.
        #expect(await eventually { session.captureState == .running(displayID: active.displayID) && capture.attempts >= 2 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(capture.maxConcurrentStarts == 1)
        #expect(capture.maxLiveStreams == 1)
        #expect(capture.liveStreams == 1)
        // And stopping really stops.
        await session.setCaptureEnabled(false)
        #expect(await eventually { capture.liveStreams == 0 })
    }

    /// Moving the display (arrangement) changes nothing captured: no restart, no hiccup.
    @Test func aMoveDoesNotRestartCapture() async throws {
        let active = try await session.startDisplay()
        #expect(await eventually { session.captureState == .running(displayID: active.displayID) })
        let startsBefore = capture.starts.count
        var configuration = session.configuration
        configuration.display.arrangement = DisplayArrangement(placement: .left, alignment: .center)
        try await session.apply(configuration)
        try await Task.sleep(for: .milliseconds(50))
        #expect(capture.starts.count == startsBefore)
    }

    /// Recreating the display (a creation-time property changed) ends with capture on the new one.
    @Test func recreatingTheDisplayEndsWithCaptureOnTheNewDisplay() async throws {
        let first = try await session.startDisplay()
        #expect(await eventually { session.captureState == .running(displayID: first.displayID) })
        var configuration = session.configuration
        configuration.display.name = "Renamed tablet"  // part of the descriptor: needs a new display
        try await session.apply(configuration)
        let second = try #require(session.activeDisplay)
        #expect(second.displayID != first.displayID)
        #expect(await eventually { session.captureState == .running(displayID: second.displayID) })
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.captureState == .running(displayID: second.displayID))  // no late stop kills it
        #expect(capture.liveStreams == 1)
    }

    /// A stream that keeps stopping right after it starts (lock screen) is retried with backoff.
    @Test func repeatedStopsBackOff() async throws {
        let displays = FakeDisplayServices()
        let slow = DisplaySession(
            provider: VirtualDisplayProvider(
                backend: FakeBackend(system: displays), displays: displays, reconfiguration: FakeReconfigurationSource(),
                timing: ProviderTiming(onlineTimeout: .milliseconds(100), pollInterval: .milliseconds(5), modeEnforcementWindow: .zero)
            ),
            capture: capture, configuration: GingaConfiguration(),
            timing: SessionTiming(initialRetryDelay: .milliseconds(100), maximumRetryDelay: .milliseconds(400))
        )
        let active = try await slow.startDisplay()
        #expect(await eventually { slow.captureState == .running(displayID: active.displayID) })
        capture.simulateUnexpectedStop(.streamStopped(code: -3808, message: "locked"))
        #expect(await eventually { slow.captureState == .retrying(attempt: 1, reason: "capture stream stopped (-3808): locked") })
        #expect(await eventually { slow.captureState == .running(displayID: active.displayID) })
        capture.simulateUnexpectedStop(.streamStopped(code: -3808, message: "locked"))
        // Stopped again right after starting: the next retry waits longer (attempt 2).
        #expect(await eventually { slow.captureState == .retrying(attempt: 2, reason: "capture stream stopped (-3808): locked") })
        #expect(await eventually { slow.captureState == .running(displayID: active.displayID) })
    }

    /// Capture runs while any consumer (tablet stream, debug preview) needs frames, and only then.
    @Test func captureFollowsDemand() async throws {
        await session.setCaptureEnabled(false)
        let active = try await session.startDisplay()
        await session.setCaptureDemand(.stream, true)
        await session.setCaptureDemand(.preview, true)
        #expect(await eventually { session.captureState == .running(displayID: active.displayID) })
        await session.setCaptureDemand(.stream, false)  // the preview still watches
        #expect(session.isCaptureEnabled)
        await session.setCaptureDemand(.preview, false)
        #expect(!session.isCaptureEnabled)
        #expect(session.captureState == .idle)
    }

    @Test func missingPermissionWaitsForTheUser() async throws {
        capture.failNextStarts(with: [.permissionDenied])
        let active = try await session.startDisplay()
        #expect(await eventually { session.captureState == .waitingForPermission })
        try await Task.sleep(for: .milliseconds(30))
        #expect(capture.attempts == 1)  // no retry loop without the user

        session.retryCapture()
        #expect(await eventually { session.captureState == .running(displayID: active.displayID) })
    }

    @Test func transientFailuresAreRetried() async throws {
        capture.failNextStarts(with: [.displayNotFound(77), .streamFailed("busy")])
        let active = try await session.startDisplay()
        #expect(await eventually { session.captureState == .running(displayID: active.displayID) })
        #expect(capture.attempts == 3)
    }

    @Test func streamThatStopsUnexpectedlyIsRestarted() async throws {
        let active = try await session.startDisplay()
        #expect(await eventually { session.captureState == .running(displayID: active.displayID) })
        capture.simulateUnexpectedStop(.streamStopped(code: -3808, message: "display asleep"))
        #expect(await eventually { capture.starts.count == 2 && session.captureState == .running(displayID: active.displayID) })
    }

    @Test func framesReachEverySink() async throws {
        _ = try await session.startDisplay()
        #expect(await eventually { capture.starts.count == 1 })
        let first = LockedValue(0)
        let second = LockedValue(0)
        _ = session.frames.add { _ in first.update { $0 += 1 } }
        let token = session.frames.add { _ in second.update { $0 += 1 } }

        capture.emit(makeFrame(sequence: 1))
        session.frames.remove(token)
        capture.emit(makeFrame(sequence: 2))

        #expect(first.value == 2)
        #expect(second.value == 1)
    }

    @Test func retryBackoffDoublesAndIsCapped() {
        let timing = SessionTiming(initialRetryDelay: .milliseconds(500), maximumRetryDelay: .seconds(5))
        #expect(timing.retryDelay(attempt: 1) == .milliseconds(500))
        #expect(timing.retryDelay(attempt: 2) == .seconds(1))
        #expect(timing.retryDelay(attempt: 4) == .seconds(4))
        #expect(timing.retryDelay(attempt: 5) == .seconds(5))
        #expect(timing.retryDelay(attempt: 50) == .seconds(5))
    }
}
