import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import GingaCore
import Testing
@testable import DisplayCapture

@Suite("CaptureSizing")
struct CaptureSizingTests {
    let panel = PixelSize(width: 2560, height: 1600)

    @Test func nativeRetinaModeIsCapturedOneToOne() {
        #expect(CaptureSizing.outputSize(displayPixels: panel, maxOutputSize: panel) == panel)
    }

    @Test func scaledModesAreDownsampledToThePanel() {
        // "Looks like 1440×900" renders 2880×1800 px; the tablet only has 2560×1600.
        #expect(CaptureSizing.outputSize(displayPixels: PixelSize(width: 2880, height: 1800), maxOutputSize: panel) == panel)
    }

    @Test func smallerModesAreNotUpscaled() {
        #expect(CaptureSizing.outputSize(displayPixels: PixelSize(width: 2048, height: 1280), maxOutputSize: panel) == PixelSize(width: 2048, height: 1280))
    }

    @Test func portraitDisplayIsBoundedByThePortraitPanel() {
        let size = CaptureSizing.outputSize(displayPixels: PixelSize(width: 1800, height: 2880), maxOutputSize: panel)
        #expect(size == PixelSize(width: 1600, height: 2560))
    }

    @Test func withoutABoundTheDisplaySizeIsUsed() {
        #expect(CaptureSizing.outputSize(displayPixels: PixelSize(width: 5120, height: 3200), maxOutputSize: nil) == PixelSize(width: 5120, height: 3200))
    }

    @Test func outputDimensionsAreEven() {
        let size = CaptureSizing.outputSize(displayPixels: PixelSize(width: 2881, height: 1801), maxOutputSize: nil)
        #expect(size.width % 2 == 0 && size.height % 2 == 0)
    }
}

@Suite("CaptureConfiguration")
struct CaptureConfigurationTests {
    @Test func defaultsFavourTheHardwareEncoder() {
        let configuration = CaptureConfiguration(frameRate: 60)
        #expect(configuration.pixelFormat == .yuv420VideoRange)
        #expect(configuration.pixelFormat.osType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        #expect(configuration.showsCursor)
        #expect(configuration.queueDepth == 5)
    }

    @Test func requestsFramesFasterThanTheRefreshRateToAvoidPacingLoss() {
        // Asking for exactly 1/60 s on a 60 Hz display yields ~51 fps; ask for 1/120 s.
        #expect(CaptureConfiguration(frameRate: 60).minimumFrameInterval == CMTime(value: 1, timescale: 120))
        #expect(CaptureConfiguration(frameRate: 120).minimumFrameInterval == CMTime(value: 1, timescale: 240))
        // A 60 fps cap on a 120 Hz display: slightly under 1/60 s so frames land every 2nd vsync.
        let capped = CaptureConfiguration(frameRate: 60, frameIntervalHeadroom: 1.15).minimumFrameInterval
        #expect(abs(capped.seconds - 1 / 69.0) < 0.0001)
    }

    @Test func mapsOntoScreenCaptureKit() {
        var configuration = CaptureConfiguration(frameRate: 60)
        configuration.showsCursor = false
        configuration.queueDepth = 6
        let stream = configuration.streamConfiguration(outputSize: PixelSize(width: 2560, height: 1600))
        #expect(stream.width == 2560)
        #expect(stream.height == 1600)
        #expect(stream.pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        #expect(stream.minimumFrameInterval.seconds == 1 / 120.0)
        #expect(stream.queueDepth == 6)
        #expect(!stream.showsCursor)
        #expect(!stream.capturesAudio)
        #expect(stream.colorMatrix as String == kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String)
        #expect(stream.colorSpaceName as String == CGColorSpace.sRGB as String)
    }

    @Test func validationRejectsOutOfRangeValues() {
        var configuration = CaptureConfiguration(frameRate: 0)
        #expect(throws: CaptureConfigurationError.frameRateOutOfRange(0)) { try configuration.validate() }
        configuration = CaptureConfiguration(frameRate: 60)
        configuration.queueDepth = 2
        #expect(throws: CaptureConfigurationError.queueDepthOutOfRange(2)) { try configuration.validate() }
        configuration.queueDepth = 9
        #expect(throws: CaptureConfigurationError.queueDepthOutOfRange(9)) { try configuration.validate() }
    }

    @Test func decodesSparseJSONWithDefaults() throws {
        let configuration = try JSONDecoder().decode(CaptureConfiguration.self, from: Data(#"{"frameRate":120,"pixelFormat":"BGRA"}"#.utf8))
        #expect(configuration.frameRate == 120)
        #expect(configuration.pixelFormat == .bgra)
        #expect(configuration.queueDepth == 5)
        #expect(configuration.showsCursor)
    }
}

@Suite("FrameMetadata")
struct FrameMetadataTests {
    let timebase = HostTimebase(numer: 125, denom: 3)

    @Test func parsesACompleteFrame() {
        let attachments: [SCStreamFrameInfo: Any] = [
            .status: NSNumber(value: SCFrameStatus.complete.rawValue),
            .displayTime: NSNumber(value: UInt64(24_000_000)),
            .dirtyRects: [NSDictionary(), NSDictionary()],
            .contentScale: NSNumber(value: 1.0),
            .scaleFactor: NSNumber(value: 2.0),
        ]
        let metadata = FrameMetadata(attachments: attachments, timebase: timebase)
        #expect(metadata.status == .complete)
        #expect(metadata.displayTime == MediaTime(nanoseconds: 1_000_000_000))
        #expect(metadata.dirtyRectCount == 2)
        #expect(metadata.contentScale == 1.0)
        #expect(metadata.scaleFactor == 2.0)
    }

    @Test func idleFramesCarryNoTimestamp() {
        let metadata = FrameMetadata(attachments: [.status: NSNumber(value: SCFrameStatus.idle.rawValue)], timebase: timebase)
        #expect(metadata.status == .idle)
        #expect(metadata.displayTime == nil)
    }

    @Test func missingOrUnknownStatusIsUnknown() {
        #expect(FrameMetadata(attachments: [:], timebase: timebase).status == .unknown)
        #expect(FrameMetadata(attachments: [.status: NSNumber(value: 99)], timebase: timebase).status == .unknown)
    }
}
