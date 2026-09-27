import CoreMedia
import CoreVideo
import Foundation
import os
import GingaCore
import Testing
@testable import VideoPipeline

@Suite("AnnexB")
struct AnnexBTests {
    @Test func convertsLengthPrefixedUnitsToStartCodes() throws {
        let avcc = Data([0, 0, 0, 2, 0x40, 0x01, 0, 0, 0, 3, 0x26, 0x01, 0xAF])
        let annexB = try AnnexB.fromLengthPrefixed(avcc)
        #expect(Array(annexB) == [0, 0, 0, 1, 0x40, 0x01, 0, 0, 0, 1, 0x26, 0x01, 0xAF])
    }

    @Test func convertsInPlaceWithoutChangingTheSize() throws {
        var data = Data([0, 0, 0, 2, 0x40, 0x01, 0, 0, 0, 3, 0x26, 0x01, 0xAF])
        let starts = try AnnexB.convertLengthPrefixedInPlace(&data)
        #expect(Array(data) == [0, 0, 0, 1, 0x40, 0x01, 0, 0, 0, 1, 0x26, 0x01, 0xAF])
        #expect(starts == [4, 10])
        #expect(AnnexB.split(data) == [Data([0x40, 0x01]), Data([0x26, 0x01, 0xAF])])

        var truncated = Data([0, 0, 0, 9, 0x40])
        #expect(throws: AnnexB.ConversionError.truncatedNAL(offset: 4)) { try AnnexB.convertLengthPrefixedInPlace(&truncated) }
        var slice = Data([0xFF, 0, 0, 0, 1, 0x26]).dropFirst()  // a Data slice: indices don't start at 0
        #expect(try AnnexB.convertLengthPrefixedInPlace(&slice) == [4])
        #expect(Array(slice) == [0, 0, 0, 1, 0x26])
    }

    @Test func rejectsTruncatedUnits() {
        #expect(throws: AnnexB.ConversionError.truncatedNAL(offset: 4)) {
            try AnnexB.fromLengthPrefixed(Data([0, 0, 0, 9, 0x40]))
        }
    }

    @Test func splitsThreeAndFourByteStartCodes() {
        let stream = Data([0, 0, 0, 1, 0x40, 0x01, 0, 0, 1, 0x42, 0x01, 0x05, 0, 0, 0, 1, 0x26])
        #expect(AnnexB.split(stream) == [Data([0x40, 0x01]), Data([0x42, 0x01, 0x05]), Data([0x26])])
    }

    @Test func joinAndLengthPrefixRoundTrip() throws {
        let units = [Data([0x40, 0x01]), Data([0x26, 0x01, 0x02, 0x03])]
        #expect(AnnexB.split(AnnexB.join(units)) == units)
        #expect(try AnnexB.nalUnits(lengthPrefixed: AnnexB.toLengthPrefixed(units)) == units)
    }

    @Test func classifiesNALUnitTypes() {
        #expect(VideoCodec.hevc.nalType(0x40) == 32)  // VPS
        #expect(VideoCodec.hevc.nalType(0x26) == 19)  // IDR_W_RADL
        #expect(VideoCodec.hevc.isParameterSet(0x42))  // SPS
        #expect(!VideoCodec.hevc.isParameterSet(0x02))
        #expect(VideoCodec.h264.nalType(0x67) == 7)  // SPS
        #expect(VideoCodec.h264.isParameterSet(0x68))  // PPS
        #expect(!VideoCodec.h264.isParameterSet(0x65))  // IDR slice
    }
}

@Suite("FramePacer")
struct FramePacerTests {
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int] = []
        func add(_ value: Int) { lock.withLock { values.append(value) } }
        var all: [Int] { lock.withLock { values } }
    }

    @Test func processesImmediatelyWhenIdle() {
        let recorder = Recorder()
        let pacer = FramePacer<Int> { recorder.add($0) }
        pacer.offer(1)
        #expect(recorder.all == [1])
        #expect(pacer.inFlightCount == 1)
    }

    @Test func newestWaitingFrameWinsWhileBusy() {
        let recorder = Recorder()
        let pacer = FramePacer<Int> { recorder.add($0) }
        pacer.offer(1)
        pacer.offer(2)
        pacer.offer(3)
        pacer.offer(4)
        #expect(recorder.all == [1])
        pacer.completed()
        #expect(recorder.all == [1, 4])
        #expect(pacer.droppedCount == 2)
        pacer.completed()
        #expect(pacer.inFlightCount == 0)
    }

    @Test func allowsSeveralInFlight() {
        let recorder = Recorder()
        let pacer = FramePacer<Int>(maxInFlight: 2) { recorder.add($0) }
        (1...3).forEach { pacer.offer($0) }
        #expect(recorder.all == [1, 2])
        pacer.completed()
        #expect(recorder.all == [1, 2, 3])
        #expect(pacer.droppedCount == 0)
    }
}

/// Synthetic IOSurface-backed NV12 frames with moving content.
/// Frames are immutable once made and the pattern repeats every 32 phases, so they're cached:
/// filling them pixel by pixel in a debug build costs ~60 ms each.
private let frameCache = OSAllocatedUnfairLock(uncheckedState: [String: CVPixelBuffer]())

func makeFrame(width: Int, height: Int, phase: Int) -> CVPixelBuffer {
    let key = "\(width)x\(height)@\(phase % 32)"
    if let cached = frameCache.withLockUnchecked({ $0[key] }) { return cached }
    let frame = renderFrame(width: width, height: height, phase: phase % 32)
    frameCache.withLockUnchecked { $0[key] = frame }
    return frame
}

private func renderFrame(width: Int, height: Int, phase: Int) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes, &buffer)
    let pixelBuffer = buffer!
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    let luma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)!.assumingMemoryBound(to: UInt8.self)
    let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
    for y in 0..<height {
        for x in 0..<width { luma[y * lumaStride + x] = UInt8(truncatingIfNeeded: x + y + phase * 8) }
    }
    let chroma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)!.assumingMemoryBound(to: UInt8.self)
    let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
    for y in 0..<height / 2 { memset(chroma + y * chromaStride, 128, width) }
    return pixelBuffer
}

final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [EncoderEvent] = []
    func add(_ event: EncoderEvent) { lock.withLock { events.append(event) } }
    var frames: [EncodedFrame] {
        lock.withLock { events.compactMap { if case .frame(let frame) = $0 { frame } else { nil } } }
    }
    var failures: [EncoderError] {
        lock.withLock { events.compactMap { if case .failed(let error) = $0 { error } else { nil } } }
    }
}

/// Uses the real hardware encoder (no special permission needed).
@Suite("VideoToolboxEncoder", .enabled(if: VideoToolboxEncoder.isHardwareEncoderAvailable(.hevc)))
struct VideoToolboxEncoderTests {
    let size = PixelSize(width: 640, height: 400)

    private func encode(_ codec: VideoCodec, frames: Int, forceKeyframeAt: Set<Int> = []) throws -> (EventCollector, VideoToolboxEncoder) {
        let collector = EventCollector()
        let encoder = try VideoToolboxEncoder(configuration: EncoderConfiguration(codec: codec, size: size, frameRate: 60, bitrateKbps: 4000)) { collector.add($0) }
        let start = MediaTime.now()
        for index in 0..<frames {
            encoder.encode(EncoderInput(
                pixelBuffer: makeFrame(width: size.width, height: size.height, phase: index),
                captureTime: start.advanced(by: .milliseconds(Int64(index) * 16)),
                forceKeyframe: forceKeyframeAt.contains(index)
            ))
        }
        encoder.flush()
        return (collector, encoder)
    }

    @Test func firstHEVCFrameIsAKeyframeWithInBandParameterSets() throws {
        let (collector, encoder) = try encode(.hevc, frames: 8)
        defer { encoder.invalidate() }
        #expect(collector.failures.isEmpty)
        let frames = collector.frames
        #expect(frames.count == 8)
        let first = try #require(frames.first)
        #expect(first.isKeyframe)
        #expect(first.parameterSets?.count == 3)  // VPS, SPS, PPS
        #expect(first.data.prefix(4) == AnnexB.startCode)
        let types = AnnexB.split(first.data).map { VideoCodec.hevc.nalType($0[0]) }
        #expect(Array(types.prefix(3)) == [32, 33, 34])
        #expect(frames.dropFirst().allSatisfy { !$0.isKeyframe })
        #expect(frames.map(\.frameId) == Array(1...8))
    }

    @Test func keyframesCanBeForced() throws {
        let (collector, encoder) = try encode(.hevc, frames: 6, forceKeyframeAt: [4])
        defer { encoder.invalidate() }
        let keyframes = collector.frames.filter(\.isKeyframe).map(\.frameId)
        #expect(keyframes == [1, 5])
    }

    /// Keyframes only when asked: an IDR costs a bitrate spike and, at 2560×1600, an encode longer
    /// than a 120 Hz frame. (VideoToolbox reads MaxKeyFrameInterval = 0 as "default GOP", about
    /// 30 frames, not "no limit": 156 IDRs in 39 s were measured before this was pinned.)
    @Test func noPeriodicKeyframesByDefault() throws {
        for codec in [VideoCodec.hevc, .h264] {
            let (collector, encoder) = try encode(codec, frames: 90)  // three default GOPs
            defer { encoder.invalidate() }
            #expect(collector.frames.count == 90)
            #expect(collector.frames.filter(\.isKeyframe).map(\.frameId) == [1], "codec \(codec)")
        }
    }

    @Test func encodesH264Too() throws {
        let (collector, encoder) = try encode(.h264, frames: 3)
        defer { encoder.invalidate() }
        #expect(collector.frames.first?.parameterSets?.count == 2)  // SPS, PPS
    }

    @Test func encodeLatencyIsSmall() throws {
        let (collector, encoder) = try encode(.hevc, frames: 30)
        defer { encoder.invalidate() }
        var window = SampleWindow(capacity: 30)
        collector.frames.dropFirst().forEach { window.add($0.encodeDuration.inMilliseconds) }
        let p95 = try #require(window.percentile(0.95))
        #expect(p95 < 50, "p95 encode latency \(p95) ms")
    }

    @Test func bitrateCanChangeOnALiveSession() throws {
        let (collector, encoder) = try encode(.hevc, frames: 2)
        encoder.setBitrate(kbps: 2000)
        encoder.encode(EncoderInput(pixelBuffer: makeFrame(width: size.width, height: size.height, phase: 9), captureTime: .now()))
        encoder.flush()
        encoder.invalidate()
        #expect(collector.failures.isEmpty)
        #expect(collector.frames.count == 3)
    }

    @Test func encodedStreamDecodesBackToTheSourceSize() async throws {
        let (collector, encoder) = try encode(.hevc, frames: 4)
        defer { encoder.invalidate() }
        let frames = collector.frames
        let decoder = try VideoToolboxDecoder(codec: .hevc, parameterSets: try #require(frames.first?.parameterSets))
        let decoded = LockedCounter()
        for frame in frames {
            decoder.decode(frame.data) { result in
                if case .success(let picture) = result,
                   CVPixelBufferGetWidth(picture.pixelBuffer) == 640, CVPixelBufferGetHeight(picture.pixelBuffer) == 400 {
                    decoded.increment()
                }
            }
        }
        decoder.waitForPendingFrames()
        #expect(decoded.value == frames.count)
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
