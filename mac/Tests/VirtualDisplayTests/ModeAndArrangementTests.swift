import CoreGraphics
import Testing
import Tab2MacCore
@testable import VirtualDisplay

@Suite("DisplayModeMatcher")
struct DisplayModeMatcherTests {
    private func mode(_ w: Int, _ h: Int, scale: Int, hz: Double, gui: Bool = true, id: Int32 = 0) -> DisplayModeInfo {
        DisplayModeInfo(
            modeID: id,
            size: PointSize(width: w, height: h),
            pixelSize: PixelSize(width: w * scale, height: h * scale),
            refreshRate: hz,
            isUsableForDesktopGUI: gui,
            ioFlags: 0x3
        )
    }

    @Test func distinguishesRetinaFromStandardModesOfTheSameSize() {
        let modes = [mode(1280, 800, scale: 1, hz: 60, id: 1), mode(1280, 800, scale: 2, hz: 60, id: 2)]
        let retina = DisplayModeMatcher.bestMatch(for: DisplayModeTarget(size: PointSize(width: 1280, height: 800), hiDPI: true, refreshRate: 60), in: modes)
        let standard = DisplayModeMatcher.bestMatch(for: DisplayModeTarget(size: PointSize(width: 1280, height: 800), hiDPI: false, refreshRate: 60), in: modes)
        #expect(retina?.modeID == 2)
        #expect(standard?.modeID == 1)
    }

    @Test func picksTheClosestRefreshRate() {
        let modes = [mode(1280, 800, scale: 2, hz: 60, id: 1), mode(1280, 800, scale: 2, hz: 120, id: 2)]
        let target = DisplayModeTarget(size: PointSize(width: 1280, height: 800), hiDPI: true, refreshRate: 119.88)
        #expect(DisplayModeMatcher.bestMatch(for: target, in: modes)?.modeID == 2)
    }

    @Test func ignoresModesNotUsableForTheDesktop() {
        let modes = [mode(1280, 800, scale: 2, hz: 60, gui: false)]
        let target = DisplayModeTarget(size: PointSize(width: 1280, height: 800), hiDPI: true, refreshRate: 60)
        #expect(DisplayModeMatcher.bestMatch(for: target, in: modes) == nil)
    }

    @Test func returnsNilWhenTheSizeIsNotOffered() {
        let modes = [mode(1440, 900, scale: 2, hz: 60)]
        let target = DisplayModeTarget(size: PointSize(width: 1280, height: 800), hiDPI: true, refreshRate: 60)
        #expect(DisplayModeMatcher.bestMatch(for: target, in: modes) == nil)
    }

    @Test func modeInfoReportsScaleAndNativeFlag() {
        let native = DisplayModeInfo(modeID: 0, size: PointSize(width: 1280, height: 800), pixelSize: PixelSize(width: 2560, height: 1600), refreshRate: 60, isUsableForDesktopGUI: true, ioFlags: 0x0200_0007)
        #expect(native.isHiDPI)
        #expect(native.scale == 2)
        #expect(native.isNative)
        #expect(native.matches(DisplayModeTarget(size: PointSize(width: 1280, height: 800), hiDPI: true, refreshRate: 60)))
    }
}

@Suite("DisplayArrangementPlanner")
struct DisplayArrangementPlannerTests {
    let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let tablet = PointSize(width: 1280, height: 800)

    private func origin(_ placement: DisplayArrangement.Placement, _ alignment: DisplayArrangement.Alignment) -> CGPoint? {
        DisplayArrangementPlanner.origin(for: DisplayArrangement(placement: placement, alignment: alignment), size: tablet, relativeTo: main)
    }

    @Test func automaticLeavesPlacementToMacOS() {
        #expect(origin(.automatic, .start) == nil)
    }

    @Test func placesToTheRight() {
        #expect(origin(.right, .start) == CGPoint(x: 1512, y: 0))
        #expect(origin(.right, .center) == CGPoint(x: 1512, y: 91))
        #expect(origin(.right, .end) == CGPoint(x: 1512, y: 182))
    }

    @Test func placesToTheLeft() {
        #expect(origin(.left, .start) == CGPoint(x: -1280, y: 0))
        #expect(origin(.left, .end) == CGPoint(x: -1280, y: 182))
    }

    @Test func placesAboveAndBelowUsingGlobalTopLeftCoordinates() {
        #expect(origin(.above, .start) == CGPoint(x: 0, y: -800))
        #expect(origin(.above, .center) == CGPoint(x: 116, y: -800))
        #expect(origin(.below, .end) == CGPoint(x: 232, y: 982))
    }

    @Test func slidesPastDisplaysAlreadyOnThatSide() {
        // The built-in panel sits right of an external main display; "right" must not overlap it.
        let builtIn = CGRect(x: 1512, y: 98, width: 1512, height: 982)
        let point = DisplayArrangementPlanner.origin(
            for: DisplayArrangement(placement: .right, alignment: .start), size: tablet, relativeTo: main, avoiding: [builtIn]
        )
        #expect(point == CGPoint(x: 3024, y: 0))
    }

    @Test func slidesUpwardAndLeftwardToo() {
        let occupiedAbove = CGRect(x: 0, y: -900, width: 1512, height: 900)
        let occupiedLeft = CGRect(x: -1000, y: 0, width: 1000, height: 982)
        #expect(DisplayArrangementPlanner.origin(for: DisplayArrangement(placement: .above, alignment: .start), size: tablet, relativeTo: main, avoiding: [occupiedAbove]) == CGPoint(x: 0, y: -1700))
        #expect(DisplayArrangementPlanner.origin(for: DisplayArrangement(placement: .left, alignment: .start), size: tablet, relativeTo: main, avoiding: [occupiedLeft]) == CGPoint(x: -2280, y: 0))
    }

    @Test func displaysThatOnlyTouchDoNotCount() {
        let touching = CGRect(x: 1512 + 1280, y: 0, width: 800, height: 600)  // shares an edge only
        let point = DisplayArrangementPlanner.origin(for: DisplayArrangement(placement: .right, alignment: .start), size: tablet, relativeTo: main, avoiding: [touching])
        #expect(point == CGPoint(x: 1512, y: 0))
    }

    @Test func worksRelativeToANonZeroReference() {
        let reference = CGRect(x: 100, y: 50, width: 1000, height: 600)
        let point = DisplayArrangementPlanner.origin(for: DisplayArrangement(placement: .right, alignment: .center), size: PointSize(width: 800, height: 1280), relativeTo: reference)
        #expect(point == CGPoint(x: 1100, y: -290))
    }
}

@Suite("DisplayChange")
struct DisplayChangeTests {
    @Test func decodesCoreGraphicsSummaryFlags() {
        #expect(DisplayChange(CGDisplayChangeSummaryFlags([.addFlag, .setModeFlag])) == [.added, .modeChanged])
        #expect(DisplayChange(CGDisplayChangeSummaryFlags([.removeFlag])) == [.removed])
        #expect(DisplayChange(CGDisplayChangeSummaryFlags([.movedFlag, .desktopShapeChangedFlag])) == [.moved, .desktopShapeChanged])
        #expect(DisplayChange(CGDisplayChangeSummaryFlags([.mirrorFlag])) == [.mirrored])
        #expect(DisplayChange(CGDisplayChangeSummaryFlags([.unMirrorFlag, .setMainFlag])) == [.unmirrored, .becameMain])
        #expect(DisplayChange(CGDisplayChangeSummaryFlags([.enabledFlag, .disabledFlag])) == [.enabled, .disabled])
    }

    @Test func ignoresTheBeginConfigurationPhase() {
        #expect(DisplayChange(CGDisplayChangeSummaryFlags([.beginConfigurationFlag, .setModeFlag])).isEmpty)
    }

    @Test func describesChangesForLogs() {
        #expect(DisplayChange([.added, .moved]).description == "added,moved")
    }
}
