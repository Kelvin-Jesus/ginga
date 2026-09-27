import CGVirtualDisplayBackend
import CGVirtualDisplayShim
import CoreGraphics
import Foundation
import ShimFakes
import GingaCore
import Testing
import VirtualDisplay

extension PrivateAPIFakeSuites {
@MainActor
@Suite("CGVirtualDisplayBackend")
struct CGVirtualDisplayBackendTests {
    init() {
        GingaFakeVirtualDisplay.reset()
    }

    private let descriptor = VirtualDisplayDescriptor(
        name: "Galaxy Tab S11",
        identity: DisplayIdentity(vendorID: 0x5022, productID: 0x5311, serialNumber: 3),
        maxPixels: PixelSize(width: 3200, height: 3200),
        physicalSize: PhysicalSize(widthMillimeters: 236.9, heightMillimeters: 148.1),
        colorPrimaries: .sRGB
    )
    private let modes = VirtualDisplayModeSet(hiDPI: true, modes: [
        VirtualDisplayModeSpec(size: PointSize(width: 1280, height: 800), refreshRate: 120),
        VirtualDisplayModeSpec(size: PointSize(width: 1280, height: 800), refreshRate: 60),
    ])

    @Test func availabilityFollowsTheChecker() {
        #expect(CGVirtualDisplayBackend(classResolver: fakeResolver()).availability().isAvailable)
        let broken = CGVirtualDisplayBackend(classResolver: fakeResolver(overriding: ["CGVirtualDisplayMode": nil]))
        guard case .unavailable(_, let details) = broken.availability() else {
            Issue.record("expected unavailable")
            return
        }
        #expect(details == ["class CGVirtualDisplayMode not found"])
    }

    @Test func createTranslatesDescriptorAndModes() throws {
        let backend = CGVirtualDisplayBackend(classResolver: fakeResolver())
        let id = try backend.createDisplay(descriptor, modes: modes) {}
        #expect(id == 42)
        #expect(backend.displayID == 42)

        let fake = try #require(GingaFakeVirtualDisplay.lastInstance)
        let privateDescriptor = try #require(fake.descriptor as? GingaFakeVirtualDisplayDescriptor)
        #expect(privateDescriptor.name == "Galaxy Tab S11")
        #expect(privateDescriptor.serialNumber == 3)
        #expect(privateDescriptor.maxPixelsWide == 3200)
        #expect(privateDescriptor.greenPrimary == CGPoint(x: 0.3, y: 0.6))
        let settings = try #require(fake.appliedSettings.last as? GingaFakeVirtualDisplaySettings)
        let privateModes = try #require(settings.modes as? [GingaFakeVirtualDisplayMode])
        #expect(privateModes.map(\.refreshRate) == [120, 60])
        #expect(settings.hiDPI == 1)
        backend.destroyDisplay()
    }

    @Test func creatingTwiceIsRejected() throws {
        let backend = CGVirtualDisplayBackend(classResolver: fakeResolver())
        _ = try backend.createDisplay(descriptor, modes: modes) {}
        #expect(throws: VirtualDisplayBackendError.alreadyCreated) {
            try backend.createDisplay(descriptor, modes: modes) {}
        }
        backend.destroyDisplay()
    }

    @Test func settingModesWithoutADisplayFails() {
        let backend = CGVirtualDisplayBackend(classResolver: fakeResolver())
        #expect(throws: VirtualDisplayBackendError.noDisplay) { try backend.setDisplayModes(modes) }
    }

    @Test func destroyReleasesTheDisplayAndIsIdempotent() throws {
        let before = GingaFakeVirtualDisplay.liveInstances
        let backend = CGVirtualDisplayBackend(classResolver: fakeResolver())
        _ = try backend.createDisplay(descriptor, modes: modes) {}
        backend.destroyDisplay()
        backend.destroyDisplay()
        #expect(backend.displayID == nil)
        #expect(GingaFakeVirtualDisplay.liveInstances == before)
    }

    @Test func privateErrorsMapToBackendErrors() {
        GingaFakeVirtualDisplay.applyResult = false
        let backend = CGVirtualDisplayBackend(classResolver: fakeResolver())
        #expect {
            try backend.createDisplay(descriptor, modes: modes) {}
        } throws: { error in
            guard case .settingsRejected = error as? VirtualDisplayBackendError else { return false }
            return true
        }

        GingaFakeVirtualDisplay.reset()
        GingaFakeVirtualDisplay.raiseOnInit = true
        #expect {
            try backend.createDisplay(descriptor, modes: modes) {}
        } throws: { error in
            guard case .creationFailed(let message) = error as? VirtualDisplayBackendError else { return false }
            return message.contains("NSInternalInconsistencyException")
        }

        let unavailable = CGVirtualDisplayBackend(classResolver: fakeResolver(overriding: ["CGVirtualDisplay": nil]))
        #expect {
            try unavailable.createDisplay(descriptor, modes: modes) {}
        } throws: { error in
            guard case .unavailable = error as? VirtualDisplayBackendError else { return false }
            return true
        }
    }

    @Test func terminationReachesTheCallerOnTheMainActor() async throws {
        let backend = CGVirtualDisplayBackend(classResolver: fakeResolver())
        let flag = Flag()
        _ = try backend.createDisplay(descriptor, modes: modes) { flag.isSet = true }
        GingaFakeVirtualDisplay.lastInstance?.simulateTermination()
        await waitFor { flag.isSet }
        #expect(flag.isSet)
        backend.destroyDisplay()
    }
}

}

/// Creates a real virtual display on this Mac. Opt-in because it briefly changes the display
/// layout: `GINGA_INTEGRATION=1 scripts/test.sh --filter RealVirtualDisplay`.
@MainActor
@Suite("RealVirtualDisplay", .serialized, .enabled(if: ProcessInfo.processInfo.environment["GINGA_INTEGRATION"] == "1"))
struct RealVirtualDisplayTests {
    @Test func createsAnIndependentDisplayAndRemovesIt() async throws {
        let displays = CoreGraphicsDisplayServices()
        let provider = VirtualDisplayProvider(backend: CGVirtualDisplayBackend(), displays: displays)
        let active = try await provider.start(DeviceProfile.galaxyTabS11.configuration())

        #expect(active.displayID != 0)
        #expect(active.displayID != CGMainDisplayID())
        #expect(displays.onlineDisplayIDs().contains(active.displayID))
        #expect(CGDisplayIsActive(active.displayID) != 0)
        #expect(active.isExtendingDesktop)
        #expect(CGDisplayBounds(active.displayID).width > 0)

        await provider.stop()
        #expect(!displays.onlineDisplayIDs().contains(active.displayID))
    }
}
