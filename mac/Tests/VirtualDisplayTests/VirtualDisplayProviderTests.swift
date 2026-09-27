import CoreGraphics
import Testing
import GingaCore
@testable import VirtualDisplay
import VirtualDisplayTestSupport

@MainActor
@Suite("VirtualDisplayProvider")
struct VirtualDisplayProviderTests {
    let system = FakeDisplayServices()
    let reconfiguration = FakeReconfigurationSource()
    let backend: FakeBackend
    let provider: VirtualDisplayProvider
    var events: [VirtualDisplayEvent] { recorder.events }
    private let recorder = EventRecorder()

    init() {
        backend = FakeBackend(system: system)
        provider = VirtualDisplayProvider(
            backend: backend,
            displays: system,
            reconfiguration: reconfiguration,
            timing: ProviderTiming(onlineTimeout: .milliseconds(100), pollInterval: .milliseconds(5), modeEnforcementWindow: .zero)
        )
        provider.onEvent = { [recorder] in recorder.events.append($0) }
    }

    private var tabS11: VirtualDisplayConfiguration {
        var configuration = DeviceProfile.galaxyTabS11.configuration()
        configuration.arrangement = DisplayArrangement(placement: .right, alignment: .start)
        return configuration
    }

    @Test func startCreatesDisplaySelectsTargetModeAndArranges() async throws {
        system.defaultsToLargestMode = true  // force an explicit mode switch
        var configuration = tabS11
        configuration.resolution = PointSize(width: 1440, height: 900)

        let active = try await provider.start(configuration)

        #expect(active.displayID == 77)
        #expect(backend.createdDescriptors.count == 1)
        #expect(active.mode?.size == PointSize(width: 1440, height: 900))
        #expect(active.mode?.isHiDPI == true)
        #expect(active.pixelSize == PixelSize(width: 2880, height: 1800))
        #expect(system.setModeCalls.count == 1)
        #expect(active.bounds.origin == CGPoint(x: 1512, y: 0))
        #expect(provider.state == .active(active))
        #expect(events == [.activated(active)])
        #expect(reconfiguration.isObserving)
    }

    @Test func startSkipsModeSwitchWhenTheDefaultAlreadyMatches() async throws {
        _ = try await provider.start(tabS11)
        #expect(system.setModeCalls.isEmpty)
    }

    /// An external monitor with a 60 Hz and a 100 Hz mode, currently at 60 Hz.
    private func addExternalMonitor() -> (sixty: DisplayModeInfo, hundred: DisplayModeInfo) {
        let sixty = DisplayModeInfo(
            modeID: 1, size: PointSize(width: 2560, height: 1080), pixelSize: PixelSize(width: 2560, height: 1080),
            refreshRate: 60, isUsableForDesktopGUI: true, ioFlags: 0x3
        )
        var hundred = sixty
        hundred.modeID = 2
        hundred.refreshRate = 100
        system.displays[2] = FakeDisplayServices.Display(bounds: CGRect(x: -2560, y: 0, width: 2560, height: 1080), modes: [sixty, hundred], current: sixty)
        return (sixty, hundred)
    }

    /// Adding a display makes macOS apply the configuration saved for the new set of displays
    /// (measured: an HDMI monitor switching from 2048×864@2x 60 Hz to 2560×1080 100 Hz). That
    /// per-set choice is the user's: Ginga reports it and never touches other displays.
    @Test func otherDisplaysAreNeverReconfigured() async throws {
        let monitor = addExternalMonitor()
        system.modeChangesWhenDisplayAdded = [2: monitor.hundred]

        _ = try await provider.start(tabS11)

        #expect(system.currentMode(of: 2) == monitor.hundred)
        #expect(system.setModeCalls.isEmpty)
        #expect(events.count == 1)
    }

    @Test func arrangementAvoidsOtherDisplays() async throws {
        system.displays[5] = FakeDisplayServices.Display(bounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080), modes: [], current: nil)
        let active = try await provider.start(tabS11)  // placement: right, alignment: start
        #expect(active.bounds.origin == CGPoint(x: 3432, y: 0))
    }

    @Test func automaticArrangementLeavesPlacementAlone() async throws {
        var configuration = tabS11
        configuration.arrangement = .automatic
        _ = try await provider.start(configuration)
        #expect(system.setOriginCalls.isEmpty)
    }

    @Test func unavailableBackendFailsWithoutCreatingAnything() async {
        backend.availabilityResult = .unavailable(reason: "CGVirtualDisplay missing", details: [])
        await #expect(throws: VirtualDisplayError.backendUnavailable("CGVirtualDisplay missing")) {
            try await provider.start(tabS11)
        }
        #expect(backend.createdDescriptors.isEmpty)
        #expect(provider.state == .failed("CGVirtualDisplay missing"))
    }

    @Test func invalidConfigurationIsRejectedBeforeTouchingTheBackend() async {
        var configuration = tabS11
        configuration.refreshRate = 0
        await #expect(throws: VirtualDisplayError.self) { try await provider.start(configuration) }
        #expect(backend.createdDescriptors.isEmpty)
    }

    @Test func backendCreationErrorsAreSurfaced() async {
        backend.createError = .creationFailed("displayID was 0")
        await #expect(throws: VirtualDisplayError.backend("creation failed: displayID was 0")) {
            try await provider.start(tabS11)
        }
        if case .failed = provider.state {} else { Issue.record("expected failed state, got \(provider.state)") }
    }

    @Test func displayThatNeverComesOnlineTimesOutAndIsCleanedUp() async {
        system.displaysComeOnline = false
        await #expect(throws: VirtualDisplayError.self) { try await provider.start(tabS11) }
        #expect(backend.destroyCount == 1)
        #expect(backend.displayID == nil)
    }

    @Test func startingTwiceIsRejected() async throws {
        _ = try await provider.start(tabS11)
        await #expect(throws: VirtualDisplayError.alreadyActive) { try await provider.start(tabS11) }
    }

    @Test func orientationChangeIsAppliedLiveOnTheSameDisplay() async throws {
        let first = try await provider.start(tabS11)
        var portrait = tabS11
        portrait.orientation = .portrait

        let second = try await provider.apply(portrait)

        #expect(second.displayID == first.displayID)
        #expect(backend.createdDescriptors.count == 1)
        #expect(backend.appliedModeSets.count == 2)
        #expect(second.mode?.size == PointSize(width: 800, height: 1280))
        #expect(second.bounds.size == CGSize(width: 800, height: 1280))
        #expect(second.pixelSize == PixelSize(width: 1600, height: 2560))
        #expect(events.last == .reconfigured(second))
    }

    @Test func resolutionChangeWithinAdvertisedModesOnlySwitchesMode() async throws {
        _ = try await provider.start(tabS11)
        var larger = tabS11
        larger.resolution = PointSize(width: 1600, height: 1000)

        let active = try await provider.apply(larger)

        // Same advertised modes (only the preferred one differs): switch via public CoreGraphics
        // instead of re-applying private settings, which would reconfigure the whole display.
        #expect(backend.appliedModeSets.count == 1)
        #expect(backend.createdDescriptors.count == 1)
        #expect(system.setModeCalls.count == 1)
        #expect(active.mode?.size == PointSize(width: 1600, height: 1000))
    }

    @Test func identityChangeRecreatesTheDisplay() async throws {
        let first = try await provider.start(tabS11)
        var other = tabS11
        other.identity.serialNumber = 99

        let second = try await provider.apply(other)

        #expect(backend.destroyCount == 1)
        #expect(backend.createdDescriptors.count == 2)
        #expect(second.displayID != first.displayID)
    }

    @Test func applyWhileInactiveStartsTheDisplay() async throws {
        let active = try await provider.apply(tabS11)
        #expect(provider.state == .active(active))
    }

    @Test func stopDestroysTheDisplayAndStopsObserving() async throws {
        let active = try await provider.start(tabS11)
        await provider.stop()
        #expect(backend.destroyCount == 1)
        #expect(provider.state == .inactive)
        #expect(!reconfiguration.isObserving)
        #expect(events.last == .deactivated(active.displayID))
        #expect(!system.onlineDisplayIDs().contains(active.displayID))
    }

    @Test func stopWhenInactiveIsANoOp() async {
        await provider.stop()
        #expect(backend.destroyCount == 0)
        #expect(events.isEmpty)
    }

    @Test func systemTerminationIsReportedAsLost() async throws {
        let active = try await provider.start(tabS11)
        backend.simulateSystemTermination()
        #expect(provider.state == .inactive)
        #expect(events.last == .lost(active.displayID, reason: "terminated by the system"))
    }

    @Test func modeChosenInSystemSettingsIsPickedUp() async throws {
        let active = try await provider.start(tabS11)
        system.simulateUserSelectsMode(active.displayID) { $0.size == PointSize(width: 1024, height: 640) && $0.isHiDPI }
        reconfiguration.simulate(active.displayID, .modeChanged)

        guard case .reconfigured(let updated)? = events.last else {
            Issue.record("expected reconfigured event, got \(String(describing: events.last))")
            return
        }
        #expect(updated.mode?.size == PointSize(width: 1024, height: 640))
        #expect(updated.pixelSize == PixelSize(width: 2048, height: 1280))
        #expect(provider.activeDisplay == updated)
    }

    @Test func autoMirroredDisplayIsSwitchedBackToAnExtendedDesktop() async throws {
        system.autoMirrorSource = FakeDisplayServices.builtInID
        let active = try await provider.start(tabS11)
        #expect(active.isExtendingDesktop)
        #expect(system.setMirrorCalls == [nil])
    }

    @Test func mirroringChosenLaterByTheUserIsReportedNotReverted() async throws {
        let active = try await provider.start(tabS11)
        try system.setMirrorSource(FakeDisplayServices.builtInID, of: active.displayID)
        reconfiguration.simulate(active.displayID, .mirrored)
        guard case .reconfigured(let updated)? = events.last else {
            Issue.record("expected reconfigured event")
            return
        }
        #expect(!updated.isExtendingDesktop)
        #expect(system.setMirrorCalls.count == 1)  // only the user's change
    }

    @Test func modeRestoredByMacOSRightAfterCreationIsOverridden() async throws {
        let system = FakeDisplayServices()
        let backend = FakeBackend(system: system)
        let reconfiguration = FakeReconfigurationSource()
        let provider = VirtualDisplayProvider(
            backend: backend, displays: system, reconfiguration: reconfiguration,
            timing: ProviderTiming(onlineTimeout: .milliseconds(100), pollInterval: .milliseconds(5), modeEnforcementWindow: .seconds(30))
        )
        let recorder = EventRecorder()
        provider.onEvent = { recorder.events.append($0) }
        let active = try await provider.start(tabS11)

        // WindowServer restores a mode it saved for this display identity in an earlier session.
        system.simulateUserSelectsMode(active.displayID) { $0.size == PointSize(width: 1024, height: 640) && !$0.isHiDPI }
        reconfiguration.simulate(active.displayID, .modeChanged)

        #expect(system.currentMode(of: active.displayID)?.matches(active.plan.target) == true)
        #expect(recorder.events == [.activated(active)])
    }

    @Test func changesToOtherDisplaysAreIgnored() async throws {
        _ = try await provider.start(tabS11)
        let count = events.count
        reconfiguration.simulate(FakeDisplayServices.builtInID, [.modeChanged, .moved])
        #expect(events.count == count)
    }

    @Test func unexpectedRemovalIsReportedAsLost() async throws {
        let active = try await provider.start(tabS11)
        system.simulateRemove(active.displayID)
        reconfiguration.simulate(active.displayID, .removed)
        #expect(events.last == .lost(active.displayID, reason: "removed by the system"))
        #expect(provider.state == .inactive)
    }
}

@MainActor
private final class EventRecorder {
    var events: [VirtualDisplayEvent] = []
}
