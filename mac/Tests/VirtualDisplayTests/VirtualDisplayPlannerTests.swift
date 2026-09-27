import Testing
import GingaCore
@testable import VirtualDisplay

@Suite("VirtualDisplayPlanner")
struct VirtualDisplayPlannerTests {
    let tabS11 = DeviceProfile.galaxyTabS11.configuration()

    /// 60 Hz by default (power; 120 Hz is opt-in, see `highRefreshRateAlsoAdvertisesSixtyHertzFallbacks`).
    @Test func defaultTabS11PlanIsNativeRetinaAt60Hertz() {
        let plan = VirtualDisplayPlanner.plan(for: tabS11)
        #expect(plan.modeSet.hiDPI)
        #expect(plan.modeSet.modes.first == VirtualDisplayModeSpec(size: PointSize(width: 1280, height: 800), refreshRate: 60))
        #expect(plan.target == DisplayModeTarget(size: PointSize(width: 1280, height: 800), hiDPI: true, refreshRate: 60))
        #expect(plan.expectedPixelSize == PixelSize(width: 2560, height: 1600))
    }

    @Test func advertisesEveryProfileResolutionWithPreferredFirst() {
        var configuration = tabS11
        configuration.refreshRate = 60
        let sizes = VirtualDisplayPlanner.plan(for: configuration).modeSet.modes.map(\.size)
        #expect(sizes.first == PointSize(width: 1280, height: 800))
        #expect(Set(sizes) == Set(DeviceProfile.galaxyTabS11.resolutionOptions))
        #expect(sizes.count == DeviceProfile.galaxyTabS11.resolutionOptions.count)  // no duplicates
    }

    @Test func maxPixelsIsSquareSoOrientationCanChangeLive() {
        let plan = VirtualDisplayPlanner.plan(for: tabS11)
        // Largest option is 1600×1000 pt → 3200 px at 2×; square so portrait fits too.
        #expect(plan.descriptor.maxPixels == PixelSize(width: 3200, height: 3200))
    }

    @Test func highRefreshRateAlsoAdvertisesSixtyHertzFallbacks() {
        var configuration = tabS11
        configuration.refreshRate = 120
        let modes = VirtualDisplayPlanner.plan(for: configuration).modeSet.modes
        #expect(modes.first == VirtualDisplayModeSpec(size: PointSize(width: 1280, height: 800), refreshRate: 120))
        #expect(modes.contains(VirtualDisplayModeSpec(size: PointSize(width: 1280, height: 800), refreshRate: 60)))
        let firstSixty = modes.firstIndex { $0.refreshRate == 60 }!
        let leadingAreHighRefresh = modes[..<firstSixty].allSatisfy { $0.refreshRate == 120 }
        #expect(leadingAreHighRefresh)
    }

    @Test func portraitSwapsModesTargetAndPhysicalSize() {
        var configuration = tabS11
        configuration.orientation = .portrait
        let plan = VirtualDisplayPlanner.plan(for: configuration)
        let allPortrait = plan.modeSet.modes.allSatisfy { $0.size.isPortrait }
        #expect(allPortrait)
        #expect(plan.target.size == PointSize(width: 800, height: 1280))
        #expect(plan.expectedPixelSize == PixelSize(width: 1600, height: 2560))
        #expect(plan.descriptor.physicalSize == configuration.panel.physicalSize.swapped)
        #expect(plan.descriptor.maxPixels == PixelSize(width: 3200, height: 3200))
    }

    @Test func standardResolutionUsesOnePixelPerPoint() {
        var configuration = tabS11
        configuration.hiDPI = false
        configuration.resolution = PointSize(width: 2560, height: 1600)
        configuration.extraResolutions = []
        let plan = VirtualDisplayPlanner.plan(for: configuration)
        #expect(!plan.modeSet.hiDPI)
        #expect(plan.expectedPixelSize == PixelSize(width: 2560, height: 1600))
        #expect(plan.descriptor.maxPixels == PixelSize(width: 2560, height: 2560))
    }

    @Test func descriptorCarriesIdentityNameAndSRGBPrimaries() {
        let plan = VirtualDisplayPlanner.plan(for: tabS11)
        #expect(plan.descriptor.name == "Galaxy Tab S11")
        #expect(plan.descriptor.identity == tabS11.identity)
        #expect(plan.descriptor.colorPrimaries == .sRGB)
    }

    @Test func orientationChangeDoesNotRequireRecreation() {
        var portrait = tabS11
        portrait.orientation = .portrait
        let before = VirtualDisplayPlanner.plan(for: tabS11).descriptor
        let after = VirtualDisplayPlanner.plan(for: portrait).descriptor
        #expect(!after.requiresRecreation(comparedTo: before))
    }

    @Test func identityChangeRequiresRecreation() {
        var other = tabS11
        other.identity.serialNumber += 1
        let before = VirtualDisplayPlanner.plan(for: tabS11).descriptor
        #expect(VirtualDisplayPlanner.plan(for: other).descriptor.requiresRecreation(comparedTo: before))
    }

    @Test func growingBeyondMaxPixelsRequiresRecreationButShrinkingDoesNot() {
        var bigger = tabS11
        bigger.extraResolutions.append(PointSize(width: 1920, height: 1200))
        var smaller = tabS11
        smaller.extraResolutions = []
        let before = VirtualDisplayPlanner.plan(for: tabS11).descriptor
        #expect(VirtualDisplayPlanner.plan(for: bigger).descriptor.requiresRecreation(comparedTo: before))
        #expect(!VirtualDisplayPlanner.plan(for: smaller).descriptor.requiresRecreation(comparedTo: before))
    }
}
