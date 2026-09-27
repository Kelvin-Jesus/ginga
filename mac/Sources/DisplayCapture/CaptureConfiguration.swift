import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit
import GingaCore

public enum CapturePixelFormat: String, Codable, Sendable, CaseIterable {
    /// NV12, BT.709 video range — consumed directly (zero-copy) by the hardware H.264/HEVC encoder.
    /// Video range also avoids Android decoders that mishandle full-range streams.
    case yuv420VideoRange = "420v"
    case yuv420FullRange = "420f"
    /// 8-bit BGRA — for debugging / snapshots.
    case bgra = "BGRA"

    public var osType: OSType {
        switch self {
        case .yuv420VideoRange: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        case .yuv420FullRange: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        case .bgra: kCVPixelFormatType_32BGRA
        }
    }

    public var isYUV: Bool { self != .bgra }
}

public enum CaptureColorSpace: String, Codable, Sendable, CaseIterable {
    case sRGB
    case displayP3

    var name: CFString {
        switch self {
        case .sRGB: CGColorSpace.sRGB
        case .displayP3: CGColorSpace.displayP3
        }
    }
}

public struct CaptureConfiguration: Hashable, Sendable {
    /// The display's refresh rate; capture never produces more frames than WindowServer composes.
    public var frameRate: Double
    /// Upper bound for the output (normally the receiving panel, orientation-agnostic). nil = display pixels.
    public var maxOutputSize: PixelSize?
    /// ScreenCaptureKit is asked for frames `headroom`× faster than `frameRate`: requesting exactly
    /// 1/60 s on a 60 Hz display measurably drops to ~51 fps.
    public var frameIntervalHeadroom: Double
    public var pixelFormat: CapturePixelFormat
    /// Virtual displays have no hardware cursor overlay, so it must be composited into the frames.
    public var showsCursor: Bool
    /// Surfaces in flight; consumers must release frames within `minimumFrameInterval × (queueDepth − 1)`.
    public var queueDepth: Int
    public var colorSpace: CaptureColorSpace

    public init(
        frameRate: Double,
        maxOutputSize: PixelSize? = nil,
        frameIntervalHeadroom: Double = 2,
        pixelFormat: CapturePixelFormat = .yuv420VideoRange,
        showsCursor: Bool = true,
        queueDepth: Int = 5,
        colorSpace: CaptureColorSpace = .sRGB
    ) {
        self.frameRate = frameRate
        self.maxOutputSize = maxOutputSize
        self.frameIntervalHeadroom = frameIntervalHeadroom
        self.pixelFormat = pixelFormat
        self.showsCursor = showsCursor
        self.queueDepth = queueDepth
        self.colorSpace = colorSpace
    }

    public static let supportedFrameRates = 1.0...240.0
    public static let supportedQueueDepths = 3...8

    public var minimumFrameInterval: CMTime {
        CMTime(value: 1_000, timescale: CMTimeScale((frameRate * frameIntervalHeadroom * 1_000).rounded()))
    }

    public func validate() throws(CaptureConfigurationError) {
        guard Self.supportedFrameRates.contains(frameRate) else { throw .frameRateOutOfRange(frameRate) }
        guard Self.supportedQueueDepths.contains(queueDepth) else { throw .queueDepthOutOfRange(queueDepth) }
        guard frameIntervalHeadroom >= 1 else { throw .invalidHeadroom(frameIntervalHeadroom) }
    }

    /// The ScreenCaptureKit configuration for a given output size. (Never read `colorMatrix` or
    /// `colorSpaceName` from a fresh SCStreamConfiguration: their unset values crash when bridged.)
    public func streamConfiguration(outputSize: PixelSize) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = outputSize.width
        configuration.height = outputSize.height
        configuration.minimumFrameInterval = minimumFrameInterval
        configuration.pixelFormat = pixelFormat.osType
        configuration.showsCursor = showsCursor
        configuration.queueDepth = queueDepth
        configuration.capturesAudio = false
        configuration.colorSpaceName = colorSpace.name
        if pixelFormat.isYUV {
            configuration.colorMatrix = kCVImageBufferYCbCrMatrix_ITU_R_709_2
        }
        configuration.backgroundColor = CGColor.black
        return configuration
    }
}

public enum CaptureConfigurationError: Error, Hashable, Sendable, CustomStringConvertible {
    case frameRateOutOfRange(Double)
    case queueDepthOutOfRange(Int)
    case invalidHeadroom(Double)

    public var description: String {
        switch self {
        case .frameRateOutOfRange(let rate): "frame rate \(rate) outside \(CaptureConfiguration.supportedFrameRates)"
        case .queueDepthOutOfRange(let depth): "queue depth \(depth) outside \(CaptureConfiguration.supportedQueueDepths)"
        case .invalidHeadroom(let headroom): "frame interval headroom \(headroom) must be ≥ 1"
        }
    }
}

extension CaptureConfiguration: Codable {
    enum CodingKeys: String, CodingKey {
        case frameRate, maxOutputSize, frameIntervalHeadroom, pixelFormat, showsCursor, queueDepth, colorSpace
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            frameRate: try container.decodeIfPresent(Double.self, forKey: .frameRate) ?? 60,
            maxOutputSize: try container.decodeIfPresent(PixelSize.self, forKey: .maxOutputSize),
            frameIntervalHeadroom: try container.decodeIfPresent(Double.self, forKey: .frameIntervalHeadroom) ?? 2,
            pixelFormat: try container.decodeIfPresent(CapturePixelFormat.self, forKey: .pixelFormat) ?? .yuv420VideoRange,
            showsCursor: try container.decodeIfPresent(Bool.self, forKey: .showsCursor) ?? true,
            queueDepth: try container.decodeIfPresent(Int.self, forKey: .queueDepth) ?? 5,
            colorSpace: try container.decodeIfPresent(CaptureColorSpace.self, forKey: .colorSpace) ?? .sRGB
        )
    }
}

public enum CaptureSizing {
    /// Output size for a display whose backing store is `displayPixels`: aspect-fit into the
    /// bound (matched to the display's orientation), never upscaled, even dimensions for 4:2:0.
    public static func outputSize(displayPixels: PixelSize, maxOutputSize: PixelSize?) -> PixelSize {
        guard let maxOutputSize else { return displayPixels.roundedDownToEven }
        let bound = displayPixels.isPortrait == maxOutputSize.isPortrait ? maxOutputSize : maxOutputSize.swapped
        return displayPixels.aspectFit(within: bound).roundedDownToEven
    }
}

public enum DisplayGeometry {
    /// Backing-store size of the display's current mode (points × scale).
    public static func pixelSize(of display: CGDirectDisplayID) -> PixelSize? {
        guard let mode = CGDisplayCopyDisplayMode(display) else { return nil }
        return PixelSize(width: mode.pixelWidth, height: mode.pixelHeight)
    }
}

public enum ScreenCapturePermission {
    /// Whether this process may capture the screen (Privacy & Security › Screen & System Audio Recording).
    public static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks the system for access (shows the prompt the first time). Returns the current state.
    @discardableResult
    public static func request() -> Bool { CGRequestScreenCaptureAccess() }
}
