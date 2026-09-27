import CoreGraphics
import DisplayCapture
import Foundation
import GingaCore
import GingaSession
import Testing
import VirtualDisplay
import VirtualDisplayTestSupport
@testable import GingaStreaming

/// Capture that accepts every start and never produces frames.
private final class IdleCaptureSource: DisplayCaptureSource, @unchecked Sendable {
    func start(
        displayID: CGDirectDisplayID,
        configuration: CaptureConfiguration,
        onFrame: @escaping @Sendable (CapturedFrame) -> Void,
        onStop: @escaping @Sendable (CaptureError) -> Void
    ) async throws(CaptureError) {}

    func stop() async {}

    var statistics: CaptureStatisticsSnapshot { CaptureStatisticsSnapshot() }
}

@MainActor
@Suite("DisplayStreamHost")
struct DisplayStreamHostTests {
    let system = FakeDisplayServices()
    let backend: FakeBackend
    let session: DisplaySession
    let host: DisplayStreamHost

    init() {
        backend = FakeBackend(system: system)
        let provider = VirtualDisplayProvider(
            backend: backend, displays: system, reconfiguration: FakeReconfigurationSource(),
            timing: ProviderTiming(onlineTimeout: .milliseconds(300), pollInterval: .milliseconds(5), modeEnforcementWindow: .zero)
        )
        var configuration = GingaConfiguration()
        configuration.streaming.displayLingerSeconds = 0.05
        session = DisplaySession(provider: provider, capture: IdleCaptureSource(), configuration: configuration, captureEnabled: false)
        host = DisplayStreamHost(session: session)
    }

    /// Like Sidecar: the display a tablet brought goes away with it, so no window is stranded.
    @Test func aDisplayCreatedForTheTabletIsRemovedAfterItDisconnects() async throws {
        let lease = try await host.prepareForStreaming()
        #expect(session.activeDisplay != nil)
        #expect(await eventually { session.isCaptureEnabled })
        lease.release()
        #expect(await eventually { session.activeDisplay == nil })
        #expect(!session.isCaptureEnabled)
        #expect(!host.hasReceivers)
    }

    @Test func reconnectingWithinTheGracePeriodKeepsTheDisplay() async throws {
        let first = try await host.prepareForStreaming()
        let display = try #require(session.activeDisplay).displayID
        first.release()
        let second = try await host.prepareForStreaming()  // e.g. a brief USB or Wi‑Fi drop
        try await Task.sleep(for: .milliseconds(150))
        #expect(session.activeDisplay?.displayID == display)
        #expect(session.isCaptureEnabled)
        #expect(backend.createdDescriptors.count == 1)
        second.release()
    }

    /// The grace period ran out just as the tablet came back: the removal is already under way
    /// (WindowServer takes a while), so the tablet must get a fresh display, not the dying one.
    @Test func reconnectingWhileTheDisplayIsBeingRemovedGetsAFreshDisplay() async throws {
        backend.removalDelay = .milliseconds(100)
        let first = try await host.prepareForStreaming()
        let old = try #require(session.activeDisplay).displayID
        first.release()
        #expect(await eventually(timeout: .seconds(2)) { backend.destroyCount == 1 })  // removal started
        let second = try await host.prepareForStreaming()
        let fresh = try #require(session.activeDisplay)
        #expect(fresh.displayID != old)
        #expect(session.displayOwner == .stream)
        #expect(await eventually { session.isCaptureEnabled })
        second.release()
    }

    @Test func aDisplayTheUserCreatedStays() async throws {
        try await session.startDisplay()
        let lease = try await host.prepareForStreaming()
        lease.release()
        try await Task.sleep(for: .milliseconds(150))
        #expect(session.activeDisplay != nil)
        #expect(session.displayOwner == .user)
    }

    @Test func pausingWithdrawsTheStreamsCaptureDemand() async throws {
        let lease = try await host.prepareForStreaming()
        #expect(await eventually { session.isCaptureEnabled })
        lease.setPaused(true)
        #expect(await eventually { !session.isCaptureEnabled })
        #expect(session.activeDisplay != nil)  // paused, not gone
        lease.setPaused(false)
        #expect(await eventually { session.isCaptureEnabled })
        lease.release()
    }

    /// Capture runs while any receiver wants frames; the display stays while any holds it.
    @Test func demandFollowsEveryReceiver() async throws {
        let first = try await host.prepareForStreaming()
        let second = try await host.prepareForStreaming()
        #expect(backend.createdDescriptors.count == 1)
        first.setPaused(true)
        try await Task.sleep(for: .milliseconds(30))
        #expect(session.isCaptureEnabled)
        second.release()
        #expect(await eventually { !session.isCaptureEnabled })
        try await Task.sleep(for: .milliseconds(150))
        #expect(session.activeDisplay != nil)  // the paused receiver still holds it
        first.release()
        #expect(await eventually { session.activeDisplay == nil })
    }

    /// Receivers arriving together share one display.
    @Test func concurrentReceiversShareOneDisplay() async throws {
        async let a = host.prepareForStreaming()
        async let b = host.prepareForStreaming()
        let leases = try await [a, b]
        #expect(backend.createdDescriptors.count == 1)
        #expect(session.activeDisplay != nil)
        leases.forEach { $0.release() }
        #expect(await eventually { session.activeDisplay == nil })
    }

    /// A display that can't be created leaves nothing behind: no lease, no capture demand.
    @Test func aFailedStartReleasesItsLease() async throws {
        backend.createError = .creationFailed("no display for you")
        await #expect(throws: VirtualDisplayError.self) { try await host.prepareForStreaming() }
        #expect(!host.hasReceivers)
        try await Task.sleep(for: .milliseconds(30))
        #expect(!session.isCaptureEnabled)
    }

    /// The pointer leaves the video only while every receiver draws it itself.
    @Test func thePointerLeavesTheVideoOnlyWhileEveryReceiverDrawsIt() async throws {
        try #require(host.supportsCursor, "no pointer image in this environment")
        let drawing = try await host.prepareForStreaming(drawsCursor: true)
        #expect(!session.cursorInCapture)
        let plain = try await host.prepareForStreaming(drawsCursor: false)
        #expect(session.cursorInCapture)
        plain.release()
        #expect(!session.cursorInCapture)
        drawing.release()
        #expect(session.cursorInCapture)
    }

    /// Another device than the configured one gets a display shaped for it, and the user's rate
    /// is capped at what its panel can show.
    @Test func aDisplayCreatedForAnotherDeviceTakesItsPanel() async throws {
        let s9 = ReceiverPanel(model: "SM-X610", deviceId: "s9", widthPx: 2560, heightPx: 1600, densityDpi: 240, refreshRates: [60, 90])
        let lease = try await host.prepareForStreaming(drawsCursor: false, receiver: s9)
        let active = try #require(session.activeDisplay)
        #expect(active.configuration.profileID == "galaxy-tab-s9-fe-plus")
        #expect(active.configuration.panel.maxRefreshRate == 90)
        #expect(session.effectiveDisplay.refreshRate == 60)
        var faster = session.configuration
        faster.display.refreshRate = 120
        try await session.apply(faster)
        #expect(session.effectiveDisplay.refreshRate == 90)  // 120 asked, the S9 FE+ tops out at 90
        lease.release()
        #expect(await eventually { session.activeDisplay == nil })
        #expect(session.tabletDisplay == nil)
    }

    @Test func theConfiguredDeviceAndUnknownOnesAreHandled() async throws {
        let s11 = ReceiverPanel(model: "SM-X730", deviceId: "s11", widthPx: 2560, heightPx: 1600, densityDpi: 274, refreshRates: [60, 120])
        #expect(host.tabletDisplay(for: s11) == nil)  // the configuration already describes it
        let unknown = ReceiverPanel(model: "Pixel Tablet", deviceId: "pt", widthPx: 1600, heightPx: 2560, densityDpi: 276, refreshRates: [60])
        let display = try #require(host.tabletDisplay(for: unknown))
        #expect(display.panel.nativePixels == PixelSize(width: 2560, height: 1600))  // landscape
        #expect(display.resolution == PointSize(width: 1280, height: 800))
        #expect(display.name == "Pixel Tablet")
        let other = try #require(host.tabletDisplay(for: ReceiverPanel(model: "Pixel Tablet", deviceId: "other", widthPx: 1600, heightPx: 2560, densityDpi: 276, refreshRates: [60])))
        #expect(other.identity.serialNumber != display.identity.serialNumber)  // macOS remembers each one
        var off = session.configuration
        off.streaming.matchTabletDisplay = false
        try await session.apply(off)
        #expect(host.tabletDisplay(for: unknown) == nil)
    }

    @Test func releaseIsIdempotent() async throws {
        let lease = try await host.prepareForStreaming()
        lease.release()
        lease.release()
        lease.setPaused(false)  // ignored once released
        #expect(lease.isReleased)
        #expect(await eventually { session.activeDisplay == nil })
    }
}
