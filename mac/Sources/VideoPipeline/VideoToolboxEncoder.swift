@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
import Foundation
import os
import Tab2MacCore
@preconcurrency import VideoToolbox

public struct EncoderConfiguration: Hashable, Sendable, Codable {
    public var codec: VideoCodec
    public var size: PixelSize
    public var frameRate: Double
    public var bitrateKbps: Int
    /// Periodic keyframes; nil (default) sends them only on request (new receiver, loss, resume).
    /// Every link is reliable and the receiver asks when it lost something, while an IDR costs a
    /// bitrate spike and, at 2560×1600, an encode well over a 120 Hz frame time.
    public var maxKeyframeIntervalSeconds: Double?
    /// VideoToolbox low-latency rate control (H.264 profile for lossy Wi‑Fi, M8). Off by default:
    /// normal-mode HEVC measured faster on M4 (5.5 ms vs 9–10 ms at 1600p, research §3).
    public var lowLatencyRateControl: Bool
    /// `RealTime=true` makes the encoder pace itself for power (p90 roughly doubles); keep off.
    public var realTime: Bool
    /// ExpectedFrameRate = frameRate × this. 2× keeps the encoder clocked for minimum latency;
    /// 1× lets it spread each frame over the frame time (less power, longer encodes).
    public var expectedFrameRateFactor: Double
    /// The `MaximizePowerEfficiency` hint.
    public var maximizePowerEfficiency: Bool

    public init(
        codec: VideoCodec = .hevc,
        size: PixelSize,
        frameRate: Double = 60,
        bitrateKbps: Int = 40_000,
        maxKeyframeIntervalSeconds: Double? = nil,
        lowLatencyRateControl: Bool = false,
        realTime: Bool = false,
        expectedFrameRateFactor: Double = 2,
        maximizePowerEfficiency: Bool = false
    ) {
        self.codec = codec
        self.size = size
        self.frameRate = frameRate
        self.bitrateKbps = bitrateKbps
        self.maxKeyframeIntervalSeconds = maxKeyframeIntervalSeconds
        self.lowLatencyRateControl = lowLatencyRateControl
        self.realTime = realTime
        self.expectedFrameRateFactor = expectedFrameRateFactor
        self.maximizePowerEfficiency = maximizePowerEfficiency
    }
}

public enum EncoderError: Error, Hashable, Sendable, CustomStringConvertible {
    case sessionCreationFailed(OSStatus)
    case encodeFailed(OSStatus)
    case outputInvalid(String)
    case invalidated

    public var description: String {
        switch self {
        case .sessionCreationFailed(let status): "VTCompressionSessionCreate failed (\(status))"
        case .encodeFailed(let status): "encode failed (\(status))"
        case .outputInvalid(let reason): "invalid encoder output: \(reason)"
        case .invalidated: "encoder was invalidated"
        }
    }
}

/// One encoded access unit, ready for VIDEO_FRAME.
public struct EncodedFrame: Sendable {
    public var frameId: UInt32
    /// When WindowServer composed the source frame.
    public var captureTime: MediaTime
    public var encodeDuration: Duration
    public var isKeyframe: Bool
    /// Annex‑B; keyframes carry their parameter sets in-band.
    public var data: Data
    /// Parameter sets (VPS/SPS/PPS or SPS/PPS) on keyframes.
    public var parameterSets: [Data]?
}

/// A frame waiting to be encoded. `@unchecked Sendable`: IOSurface-backed capture buffers are
/// immutable after delivery and safe to hand between threads.
public struct EncoderInput: @unchecked Sendable {
    public var pixelBuffer: CVPixelBuffer
    public var captureTime: MediaTime
    public var forceKeyframe: Bool

    public init(pixelBuffer: CVPixelBuffer, captureTime: MediaTime, forceKeyframe: Bool = false) {
        self.pixelBuffer = pixelBuffer
        self.captureTime = captureTime
        self.forceKeyframe = forceKeyframe
    }
}

public enum EncoderEvent: Sendable {
    case frame(EncodedFrame)
    /// The encoder dropped the frame (for example low-latency mode at its QP cap).
    case dropped(frameId: UInt32)
    case failed(EncoderError)
}

/// Hardware HEVC/H.264 encoder (VideoToolbox), configured per research §3.
///
/// `@unchecked Sendable`: the compression session is thread-safe for encoding; mutable state is
/// behind `lock`. Output events arrive on VideoToolbox's callback thread.
public final class VideoToolboxEncoder: @unchecked Sendable {
    public let configuration: EncoderConfiguration
    private var session: VTCompressionSession?
    private let lock = NSLock()
    private var nextFrameId: UInt32 = 1
    private let output: @Sendable (EncoderEvent) -> Void

    public init(configuration: EncoderConfiguration, output: @escaping @Sendable (EncoderEvent) -> Void) throws(EncoderError) {
        self.configuration = configuration
        self.output = output

        var specification: [CFString: Any] = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true]
        if configuration.lowLatencyRateControl {
            specification[kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = true
        }
        let sourceAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: configuration.size.width,
            kCVPixelBufferHeightKey: configuration.size.height,
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
        ]
        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(configuration.size.width),
            height: Int32(configuration.size.height),
            codecType: configuration.codec.codecType,
            encoderSpecification: specification as CFDictionary,
            imageBufferAttributes: sourceAttributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &created
        )
        guard status == noErr, let created else { throw .sessionCreationFailed(status) }
        session = created
        configure(created)
        VTCompressionSessionPrepareToEncodeFrames(created)
        Log.encoder.info("encoder.created codec=\(configuration.codec.rawValue, privacy: .public) size=\(configuration.size.description, privacy: .public) fps=\(configuration.frameRate) kbps=\(configuration.bitrateKbps) lowLatency=\(configuration.lowLatencyRateControl)")
    }

    deinit {
        if let session { VTCompressionSessionInvalidate(session) }
    }

    /// Hardware encoder availability for a codec on this Mac.
    public static func isHardwareEncoderAvailable(_ codec: VideoCodec) -> Bool {
        var list: CFArray?
        guard VTCopyVideoEncoderList(nil, &list) == noErr, let encoders = list as? [[String: Any]] else { return false }
        return encoders.contains {
            ($0[kVTVideoEncoderList_CodecType as String] as? UInt32) == codec.codecType
                && ($0[kVTVideoEncoderList_IsHardwareAccelerated as String] as? Bool) == true
        }
    }

    private func configure(_ session: VTCompressionSession) {
        let fps = configuration.frameRate
        let required: [(CFString, Any)] = [
            (kVTCompressionPropertyKey_AllowFrameReordering, false),
            (kVTCompressionPropertyKey_AverageBitRate, configuration.bitrateKbps * 1000),
            (kVTCompressionPropertyKey_ProfileLevel, configuration.codec == .hevc ? kVTProfileLevel_HEVC_Main_AutoLevel : kVTProfileLevel_H264_High_AutoLevel),
        ]
        var optional: [(CFString, Any)] = [
            (kVTCompressionPropertyKey_RealTime, configuration.realTime),
            // 2× the real rate by default so the encoder never throttles itself (research §3).
            (kVTCompressionPropertyKey_ExpectedFrameRate, fps * configuration.expectedFrameRateFactor),
            // No periodic keyframes unless configured. Zero does NOT mean "no limit" here: the HEVC
            // encoder falls back to a ~30-frame GOP (measured: 156 IDRs in 39 s), so use huge values.
            (kVTCompressionPropertyKey_MaxKeyFrameInterval, configuration.maxKeyframeIntervalSeconds.map { Int(fps * $0) } ?? Int(Int32.max)),
            (kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, configuration.maxKeyframeIntervalSeconds ?? 365 * 86_400),
            (kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2),
            (kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2),
            (kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2),
            configuration.lowLatencyRateControl
                ? (kVTCompressionPropertyKey_MaxAllowedFrameQP, 51)  // avoids 57–68% drops when scrolling
                : (kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, true),
        ]
        if configuration.maximizePowerEfficiency {
            optional.append((kVTCompressionPropertyKey_MaximizePowerEfficiency, true))
        }
        for (key, value) in required {
            let status = VTSessionSetProperty(session, key: key, value: value as CFTypeRef)
            if status != noErr { Log.encoder.error("encoder.property-failed key=\(key as String, privacy: .public) status=\(status)") }
        }
        for (key, value) in optional {
            let status = VTSessionSetProperty(session, key: key, value: value as CFTypeRef)
            if status != noErr { Log.encoder.debug("encoder.property-unsupported key=\(key as String, privacy: .public) status=\(status)") }
        }
    }

    /// Changes the target bitrate on the live session (settles within ~0.5–1 s).
    public func setBitrate(kbps: Int) {
        guard let session = lock.withLock({ session }) else { return }
        let status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: (kbps * 1000) as CFTypeRef)
        Log.encoder.info("encoder.bitrate kbps=\(kbps) status=\(status)")
    }

    public func encode(_ input: EncoderInput) {
        let frameId = takeFrameId()
        guard let session = currentSession() else {
            output(.failed(.invalidated))
            return
        }
        let submitted = MediaTime.now()
        let captureTime = input.captureTime
        let presentationTime = CMTime(value: CMTimeValue(captureTime.nanoseconds / 1000), timescale: 1_000_000)
        let properties: CFDictionary? = input.forceKeyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        let handler = Self.outputHandler(codec: configuration.codec, frameId: frameId, captureTime: captureTime, submitted: submitted, output: output)
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: input.pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: properties,
            infoFlagsOut: nil,
            outputHandler: handler
        )
        if status != noErr { output(.failed(.encodeFailed(status))) }
    }

    /// Built outside `encode` so the closure only captures plain values (this also sidesteps a
    /// Swift 6.3 region-isolation compiler crash when the closure captures the input struct).
    private static func outputHandler(
        codec: VideoCodec,
        frameId: UInt32,
        captureTime: MediaTime,
        submitted: MediaTime,
        output: @escaping @Sendable (EncoderEvent) -> Void
    ) -> VTCompressionOutputHandler {
        { status, infoFlags, sampleBuffer in
            if status != noErr {
                output(.failed(.encodeFailed(status)))
                return
            }
            guard !infoFlags.contains(.frameDropped), let sampleBuffer else {
                output(.dropped(frameId: frameId))
                return
            }
            do {
                output(.frame(try makeFrame(sampleBuffer, codec: codec, frameId: frameId, captureTime: captureTime, submitted: submitted)))
            } catch {
                output(.failed(error as? EncoderError ?? .outputInvalid(String(describing: error))))
            }
        }
    }

    private func takeFrameId() -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        let id = nextFrameId
        nextFrameId &+= 1
        return id
    }

    private func currentSession() -> VTCompressionSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    /// Emits all pending frames.
    public func flush() {
        guard let session = lock.withLock({ session }) else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    }

    public func invalidate() {
        let session: VTCompressionSession? = lock.withLock {
            defer { self.session = nil }
            return self.session
        }
        if let session { VTCompressionSessionInvalidate(session) }
    }

    private static func makeFrame(_ sample: CMSampleBuffer, codec: VideoCodec, frameId: UInt32, captureTime: MediaTime, submitted: MediaTime) throws -> EncodedFrame {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let isKeyframe = !((attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false)

        guard let block = CMSampleBufferGetDataBuffer(sample) else { throw EncoderError.outputInvalid("no data buffer") }
        let length = CMBlockBufferGetDataLength(block)
        var bytes = Data(count: length)
        let copyStatus = bytes.withUnsafeMutableBytes { pointer in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: pointer.baseAddress!)
        }
        guard copyStatus == kCMBlockBufferNoErr else { throw EncoderError.outputInvalid("copy failed (\(copyStatus))") }

        // The one copy of the frame on the Mac: converted to Annex‑B where it lies.
        let starts = try AnnexB.convertLengthPrefixedInPlace(&bytes)
        var parameterSets: [Data]?
        if isKeyframe, let format = CMSampleBufferGetFormatDescription(sample) {
            let sets = AnnexB.parameterSets(of: format, codec: codec)
            parameterSets = sets
            // Parameter sets in-band before every keyframe: receivers can (re)start at any IDR.
            let inBand = starts.contains { codec.isParameterSet(bytes[bytes.startIndex + $0]) }
            let units = inBand ? AnnexB.split(bytes).filter { !codec.isParameterSet($0.first ?? 0) } : []
            var framed = AnnexB.join(sets + units)
            if !inBand { framed.append(bytes) }
            bytes = framed
        }
        return EncodedFrame(
            frameId: frameId,
            captureTime: captureTime,
            encodeDuration: MediaTime.now() - submitted,
            isKeyframe: isKeyframe,
            data: bytes,
            parameterSets: parameterSets
        )
    }
}

extension Log {
    public static let encoder = Logger(subsystem: subsystem, category: "encoder")
}
