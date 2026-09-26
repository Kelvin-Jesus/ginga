import CoreMedia
import CoreVideo
import Foundation
import os
import VideoToolbox

public enum DecoderError: Error, Hashable, Sendable, CustomStringConvertible {
    case formatCreationFailed(OSStatus)
    case sessionCreationFailed(OSStatus)
    case decodeFailed(OSStatus)
    case invalidInput(String)

    public var description: String {
        switch self {
        case .formatCreationFailed(let status): "could not create format description (\(status))"
        case .sessionCreationFailed(let status): "VTDecompressionSessionCreate failed (\(status))"
        case .decodeFailed(let status): "decode failed (\(status))"
        case .invalidInput(let reason): "invalid input: \(reason)"
        }
    }
}

/// A decoded picture. `@unchecked Sendable`: decoder output buffers are immutable once delivered.
public struct DecodedPicture: @unchecked Sendable {
    public var pixelBuffer: CVPixelBuffer
    public var presentationTime: CMTime
}

/// VideoToolbox decoder for Annex‑B access units — the Mac-side loopback of what the tablet
/// does with MediaCodec (encoder self-tests, `t2m receive`, the "encoded" preview).
public final class VideoToolboxDecoder: @unchecked Sendable {  // immutable; the decompression session is thread-safe
    public let codec: VideoCodec
    private let format: CMVideoFormatDescription
    private let session: VTDecompressionSession

    public init(codec: VideoCodec, parameterSets: [Data]) throws(DecoderError) {
        self.codec = codec
        var created: CMFormatDescription?
        let status = Self.makeFormat(codec: codec, parameterSets: parameterSets, out: &created)
        guard status == noErr, let created else { throw .formatCreationFailed(status) }
        format = created

        let destination: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
        ]
        var decompression: VTDecompressionSession?
        let sessionStatus = VTDecompressionSessionCreate(
            allocator: nil, formatDescription: format, decoderSpecification: nil,
            imageBufferAttributes: destination as CFDictionary, outputCallback: nil, decompressionSessionOut: &decompression
        )
        guard sessionStatus == noErr, let decompression else { throw .sessionCreationFailed(sessionStatus) }
        session = decompression
    }

    deinit {
        VTDecompressionSessionInvalidate(session)
    }

    public var dimensions: CMVideoDimensions { CMVideoFormatDescriptionGetDimensions(format) }

    /// Decodes one Annex‑B access unit (in-band parameter sets are skipped). The handler runs on a
    /// VideoToolbox thread.
    public func decode(_ annexB: Data, presentationTime: CMTime = .zero, handler: @escaping @Sendable (Result<DecodedPicture, DecoderError>) -> Void) {
        let units = AnnexB.split(annexB).filter { !codec.isParameterSet($0.first ?? 0) }
        guard !units.isEmpty else {
            handler(.failure(.invalidInput("no slice NAL units")))
            return
        }
        let payload = AnnexB.toLengthPrefixed(units)
        guard let sample = makeSampleBuffer(payload, presentationTime: presentationTime) else {
            handler(.failure(.invalidInput("could not wrap the access unit")))
            return
        }
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [._EnableAsynchronousDecompression], infoFlagsOut: nil) { status, _, imageBuffer, presentation, _ in
            if status != noErr {
                handler(.failure(.decodeFailed(status)))
            } else if let imageBuffer {
                handler(.success(DecodedPicture(pixelBuffer: imageBuffer, presentationTime: presentation)))
            }
        }
        if status != noErr { handler(.failure(.decodeFailed(status))) }
    }

    public func waitForPendingFrames() {
        VTDecompressionSessionWaitForAsynchronousFrames(session)
    }

    private func makeSampleBuffer(_ payload: Data, presentationTime: CMTime) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: payload.count, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: payload.count, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        ) == kCMBlockBufferNoErr, let block else { return nil }
        let copied = payload.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: payload.count) }
        guard copied == kCMBlockBufferNoErr else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: presentationTime, decodeTimeStamp: .invalid)
        var size = payload.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample
        ) == noErr else { return nil }
        return sample
    }

    private static func makeFormat(codec: VideoCodec, parameterSets: [Data], out: inout CMFormatDescription?) -> OSStatus {
        guard !parameterSets.isEmpty else { return kCMFormatDescriptionError_InvalidParameter }
        let buffers = parameterSets.map { [UInt8]($0) }
        return withPointers(buffers) { pointers, sizes in
            switch codec {
            case .hevc:
                CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: nil, parameterSetCount: buffers.count, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &out
                )
            case .h264:
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil, parameterSetCount: buffers.count, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &out
                )
            }
        }
    }

    private static func withPointers<R>(_ buffers: [[UInt8]], _ body: (UnsafePointer<UnsafePointer<UInt8>>, UnsafePointer<Int>) -> R) -> R {
        let sizes = buffers.map(\.count)
        let pointers = buffers.map { buffer -> UnsafeMutablePointer<UInt8> in
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(buffer.count, 1))
            pointer.initialize(from: buffer, count: buffer.count)
            return pointer
        }
        defer { pointers.forEach { $0.deallocate() } }
        let constPointers = pointers.map { UnsafePointer($0) }
        return constPointers.withUnsafeBufferPointer { pointerBuffer in
            sizes.withUnsafeBufferPointer { sizeBuffer in
                body(pointerBuffer.baseAddress!, sizeBuffer.baseAddress!)
            }
        }
    }
}
