import CoreMedia
import CoreVideo
import Foundation
import os
@preconcurrency import ScreenCaptureKit
import GingaCore

public enum CaptureFrameStatus: String, Codable, Sendable {
    /// New content.
    case complete
    /// Nothing changed since the previous frame (no pixel buffer).
    case idle
    case blank, suspended, started, stopped, unknown

    init(_ status: SCFrameStatus?) {
        switch status {
        case .complete: self = .complete
        case .idle: self = .idle
        case .blank: self = .blank
        case .suspended: self = .suspended
        case .started: self = .started
        case .stopped: self = .stopped
        case .none: self = .unknown
        @unknown default: self = .unknown
        }
    }
}

/// Per-frame information ScreenCaptureKit attaches to each sample buffer.
public struct FrameMetadata: Equatable, Sendable {
    public var status: CaptureFrameStatus
    /// When WindowServer composed the frame (host clock).
    public var displayTime: MediaTime?
    public var dirtyRectCount: Int
    public var contentScale: Double
    public var scaleFactor: Double

    public init(status: CaptureFrameStatus, displayTime: MediaTime? = nil, dirtyRectCount: Int = 0, contentScale: Double = 1, scaleFactor: Double = 1) {
        self.status = status
        self.displayTime = displayTime
        self.dirtyRectCount = dirtyRectCount
        self.contentScale = contentScale
        self.scaleFactor = scaleFactor
    }

    public init(attachments: [SCStreamFrameInfo: Any], timebase: HostTimebase = .current) {
        let rawStatus = (attachments[.status] as? NSNumber)?.intValue
        let status = CaptureFrameStatus(rawStatus.flatMap(SCFrameStatus.init(rawValue:)))
        let ticks = (attachments[.displayTime] as? NSNumber)?.uint64Value
        self.init(
            status: status,
            displayTime: status == .complete ? ticks.map { MediaTime(hostTicks: $0, timebase: timebase) } : nil,
            dirtyRectCount: (attachments[.dirtyRects] as? [Any])?.count ?? 0,
            contentScale: (attachments[.contentScale] as? NSNumber)?.doubleValue ?? 1,
            scaleFactor: (attachments[.scaleFactor] as? NSNumber)?.doubleValue ?? 1
        )
    }
}

/// One captured frame, ready for a hardware encoder (IOSurface-backed, no copies made).
///
/// `@unchecked Sendable`: ScreenCaptureKit hands over immutable, IOSurface-backed buffers that
/// are safe to read from any thread. Consumers must release frames promptly (see `queueDepth`).
public struct CapturedFrame: @unchecked Sendable {
    public let sequenceNumber: UInt64
    public let pixelBuffer: CVPixelBuffer
    /// The original sample buffer (carries timing; used by the local preview).
    public let sampleBuffer: CMSampleBuffer
    public let pixelSize: PixelSize
    /// When WindowServer composed the frame.
    public let displayTime: MediaTime
    /// When the frame reached us.
    public let arrivalTime: MediaTime
    public let dirtyRectCount: Int
    public let scaleFactor: Double
}

public struct CaptureStatisticsSnapshot: Hashable, Sendable, Codable {
    public var completeFrames: Int = 0
    public var idleFrames: Int = 0
    public var otherFrames: Int = 0
    /// New frames per second over the last second.
    public var framesPerSecond: Double = 0
    /// Time between consecutive new frames at composition (pacing / jitter).
    public var frameIntervalMilliseconds: StatisticSummary?
    /// Arrival minus ScreenCaptureKit's `displayTime`. `displayTime` is the vsync the frame is
    /// composed for, so values are usually *negative*: the frame reaches us before a physical
    /// display would show it. End-to-end latency is measured against the same timestamp, i.e. as
    /// "how much later than a local monitor".
    public var captureLatencyMilliseconds: StatisticSummary?
    public var lastPixelSize: PixelSize?

    public init() {}
}

/// Pure accumulator of capture statistics (inject times for tests).
public struct CaptureStatistics: Sendable {
    private var snapshotCounters = CaptureStatisticsSnapshot()
    private var rate = RateMeter(window: .seconds(1))
    private var intervals: SampleWindow
    private var latencies: SampleWindow
    private var lastDisplayTime: MediaTime?

    public init(windowSize: Int = 240) {
        intervals = SampleWindow(capacity: windowSize)
        latencies = SampleWindow(capacity: windowSize)
    }

    public mutating func record(_ metadata: FrameMetadata, arrival: MediaTime, pixelSize: PixelSize?) {
        switch metadata.status {
        case .complete:
            snapshotCounters.completeFrames += 1
            rate.record(at: arrival)
            if let pixelSize { snapshotCounters.lastPixelSize = pixelSize }
            if let displayTime = metadata.displayTime {
                latencies.add((arrival - displayTime).inMilliseconds)
                if let lastDisplayTime { intervals.add((displayTime - lastDisplayTime).inMilliseconds) }
                lastDisplayTime = displayTime
            }
        case .idle:
            snapshotCounters.idleFrames += 1
        default:
            snapshotCounters.otherFrames += 1
        }
    }

    public mutating func snapshot(at now: MediaTime) -> CaptureStatisticsSnapshot {
        var snapshot = snapshotCounters
        snapshot.framesPerSecond = rate.rate(at: now)
        snapshot.frameIntervalMilliseconds = intervals.summary
        snapshot.captureLatencyMilliseconds = latencies.summary
        return snapshot
    }

    public mutating func reset() {
        self = CaptureStatistics(windowSize: intervals.capacity)
    }
}

/// Thread-safe wrapper shared between the capture queue and the UI.
public final class CaptureStatisticsRecorder: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: CaptureStatistics())

    public init() {}

    public func record(_ metadata: FrameMetadata, arrival: MediaTime, pixelSize: PixelSize?) {
        state.withLock { $0.record(metadata, arrival: arrival, pixelSize: pixelSize) }
    }

    public func snapshot(at now: MediaTime = .now()) -> CaptureStatisticsSnapshot {
        state.withLock { $0.snapshot(at: now) }
    }

    public func reset() {
        state.withLock { $0.reset() }
    }
}
