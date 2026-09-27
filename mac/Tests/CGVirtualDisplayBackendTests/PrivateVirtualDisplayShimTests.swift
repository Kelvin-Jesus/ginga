import CGVirtualDisplayShim
import CoreGraphics
import Foundation
import ShimFakes
import Testing

@MainActor
final class Flag {
    var isSet = false
}

@MainActor
func waitFor(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// The shim is exercised against Objective-C fakes with the private classes' exact signatures.
/// Nested in `PrivateAPIFakeSuites` because the fakes keep class-level state.
extension PrivateAPIFakeSuites {
@MainActor
@Suite("PrivateVirtualDisplayShim")
struct PrivateVirtualDisplayShimTests {
    init() {
        GingaFakeVirtualDisplay.reset()
    }

    private func spec() -> GingaVirtualDisplaySpec {
        let spec = GingaVirtualDisplaySpec()
        spec.name = "Test Display"
        spec.vendorID = 0x5022
        spec.productID = 0x5311
        spec.serialNumber = 7
        spec.maxPixelsWide = 3200
        spec.maxPixelsHigh = 3200
        spec.sizeInMillimeters = CGSize(width: 236.9, height: 148.1)
        spec.hasColorPrimaries = true
        spec.redPrimary = CGPoint(x: 0.64, y: 0.33)
        spec.greenPrimary = CGPoint(x: 0.30, y: 0.60)
        spec.bluePrimary = CGPoint(x: 0.15, y: 0.06)
        spec.whitePoint = CGPoint(x: 0.3127, y: 0.3290)
        return spec
    }

    private let modes = [
        GingaVirtualDisplayModeSpec(width: 1280, height: 800, refreshRate: 60),
        GingaVirtualDisplayModeSpec(width: 1440, height: 900, refreshRate: 60),
    ]

    private func makeDisplay(
        resolver: @escaping GingaClassResolver = fakeResolver(),
        onTermination: @escaping () -> Void = {}
    ) throws -> GingaPrivateVirtualDisplay {
        try GingaPrivateVirtualDisplay(spec: spec(), modes: modes, hiDPI: true, terminationHandler: onTermination, classResolver: resolver)
    }

    @Test func createsTheDisplayFromTheSpec() throws {
        let display = try makeDisplay()
        #expect(display.displayID == 42)
        #expect(display.isValid)

        let fake = try #require(GingaFakeVirtualDisplay.lastInstance)
        let descriptor = try #require(fake.descriptor as? GingaFakeVirtualDisplayDescriptor)
        #expect(descriptor.name == "Test Display")
        #expect(descriptor.vendorID == 0x5022)
        #expect(descriptor.productID == 0x5311)
        #expect(descriptor.serialNumber == 7)
        #expect(descriptor.maxPixelsWide == 3200)
        #expect(descriptor.maxPixelsHigh == 3200)
        #expect(descriptor.sizeInMillimeters == CGSize(width: 236.9, height: 148.1))
        #expect(descriptor.redPrimary == CGPoint(x: 0.64, y: 0.33))
        #expect(descriptor.whitePoint == CGPoint(x: 0.3127, y: 0.3290))
        #expect(descriptor.queue === DispatchQueue.main)
        #expect(descriptor.terminationHandler != nil)

        let settings = try #require(fake.appliedSettings.last as? GingaFakeVirtualDisplaySettings)
        #expect(settings.hiDPI == 1)
        let privateModes = try #require(settings.modes as? [GingaFakeVirtualDisplayMode])
        #expect(privateModes.map(\.width) == [1280, 1440])
        #expect(privateModes.map(\.height) == [800, 900])
        #expect(privateModes.allSatisfy { $0.refreshRate == 60 })
    }

    @Test func legacyDescriptorSelectorsAreUsed() throws {
        let display = try makeDisplay(resolver: fakeResolver(overriding: ["CGVirtualDisplayDescriptor": GingaFakeLegacyDescriptor.self]))
        let descriptor = try #require(GingaFakeVirtualDisplay.lastInstance?.descriptor as? GingaFakeLegacyDescriptor)
        #expect(descriptor.serialNum == 7)
        #expect(descriptor.dispatchQueue === DispatchQueue.main)
        #expect(display.isValid)
    }

    @Test func unavailableAPIFailsBeforeInstantiatingAnything() {
        #expect {
            try makeDisplay(resolver: fakeResolver(overriding: ["CGVirtualDisplay": nil]))
        } throws: { error in
            (error as? GingaPrivateDisplayError)?.code == .unavailable
        }
        #expect(GingaFakeVirtualDisplay.instancesCreated == 0)
    }

    @Test func zeroDisplayIDIsACreationFailure() {
        GingaFakeVirtualDisplay.nextDisplayID = 0
        #expect {
            try makeDisplay()
        } throws: { error in
            (error as? GingaPrivateDisplayError)?.code == .creationFailed
        }
    }

    @Test func exceptionDuringCreationBecomesAnError() {
        GingaFakeVirtualDisplay.raiseOnInit = true
        #expect {
            try makeDisplay()
        } throws: { error in
            guard let error = error as? GingaPrivateDisplayError else { return false }
            return error.code == .exception && error.localizedDescription.contains("NSInternalInconsistencyException")
        }
    }

    @Test func exceptionDuringApplyReleasesTheDisplay() {
        GingaFakeVirtualDisplay.raiseOnApply = true
        let before = GingaFakeVirtualDisplay.liveInstances
        #expect {
            try makeDisplay()
        } throws: { error in
            (error as? GingaPrivateDisplayError)?.code == .exception
        }
        #expect(GingaFakeVirtualDisplay.liveInstances == before)
    }

    @Test func rejectedSettingsAreAnError() {
        GingaFakeVirtualDisplay.applyResult = false
        #expect {
            try makeDisplay()
        } throws: { error in
            (error as? GingaPrivateDisplayError)?.code == .settingsRejected
        }
    }

    @Test func modesCanBeReplacedOnTheLiveDisplay() throws {
        let display = try makeDisplay()
        try display.applyModes([GingaVirtualDisplayModeSpec(width: 800, height: 1280, refreshRate: 120)], hiDPI: true)
        let settings = try #require(GingaFakeVirtualDisplay.lastInstance?.appliedSettings.last as? GingaFakeVirtualDisplaySettings)
        let mode = try #require((settings.modes as? [GingaFakeVirtualDisplayMode])?.first)
        #expect(mode.width == 800 && mode.height == 1280 && mode.refreshRate == 120)
    }

    @Test func emptyModeListIsRejected() throws {
        let display = try makeDisplay()
        #expect {
            try display.applyModes([], hiDPI: true)
        } throws: { error in
            (error as? GingaPrivateDisplayError)?.code == .settingsRejected
        }
    }

    @Test func invalidateReleasesThePrivateDisplay() throws {
        let before = GingaFakeVirtualDisplay.liveInstances
        let display = try makeDisplay()
        #expect(GingaFakeVirtualDisplay.liveInstances == before + 1)
        display.invalidate()
        #expect(GingaFakeVirtualDisplay.liveInstances == before)
        #expect(!display.isValid)
        #expect {
            try display.applyModes(modes, hiDPI: true)
        } throws: { error in
            (error as? GingaPrivateDisplayError)?.code == .invalidated
        }
        display.invalidate()  // idempotent
    }

    @Test func terminationHandlerIsForwarded() async throws {
        let flag = Flag()
        let display = try makeDisplay(onTermination: { MainActor.assumeIsolated { flag.isSet = true } })
        GingaFakeVirtualDisplay.lastInstance?.simulateTermination()
        await waitFor { flag.isSet }
        #expect(flag.isSet)
        withExtendedLifetime(display) {}
    }
}
}
