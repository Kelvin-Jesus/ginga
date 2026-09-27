import CoreMedia
import CoreVideo
import Foundation
import os
import GingaCore
import GingaProtocol
import Transport
import VideoPipeline

/// A receiver running on the Mac itself (`ginga receive`): speaks the same protocol as the Android
/// app, decodes with VideoToolbox and measures the pipeline end to end on a single clock, so
/// capture → encode → transport → decode can be verified without the tablet.
public final class LoopbackReceiver: @unchecked Sendable {  // results live in `state` (locked); `pingTimer` is only touched by start() and stop(), called in order by the owner
    public struct Report: Codable, Sendable {
        public var framesReceived = 0
        public var framesDecoded = 0
        public var decodeErrors = 0
        public var keyframes = 0
        public var bytesReceived = 0
        public var codec: String?
        public var streamSize: PixelSize?
        public var seconds: Double = 0
        public var framesPerSecond: Double = 0
        public var megabitsPerSecond: Double = 0
        /// Display time on the Mac → decoded here (same host clock; excludes rendering).
        public var displayToDecodedMilliseconds: StatisticSummary?
        /// Display time on the Mac → frame fully received here.
        public var displayToReceivedMilliseconds: StatisticSummary?
        /// Spacing of consecutive frames' display times: the stream's cadence.
        public var frameIntervalMilliseconds: StatisticSummary?
        /// Intervals longer than 1.5 × the median: skipped frames while content kept changing.
        public var irregularIntervals = 0
        public var decodeMilliseconds: StatisticSummary?
        public var encodeMilliseconds: StatisticSummary?
        public var roundTripMicros: Int64?
        public var closeReason: String?
    }

    private struct State {
        var report = Report()
        var decoder: VideoToolboxDecoder?
        var codec: VideoCodec?
        var endToEnd = SampleWindow(capacity: 10_000)
        var received = SampleWindow(capacity: 10_000)
        var intervals = SampleWindow(capacity: 10_000)
        var lastCaptureTime: MediaTime?
        var decode = SampleWindow(capacity: 10_000)
        var encode = SampleWindow(capacity: 10_000)
        var clock = ClockSyncEstimator()
        var pingSent: [UInt32: UInt64] = [:]
        var started: MediaTime?
        var snapshotBuffer: CVPixelBuffer?
        var closed = false
    }

    private let connection: MessageConnection
    private let decodes: Bool
    private let token: String?
    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    private var pingTimer: DispatchSourceTimer?

    /// `decode: false` only receives (a cheap sink for power benchmarks: on the real system the
    /// tablet decodes, not the Mac).
    /// - Parameter token: the server's loopback token (`Ginga.app --loopback-token`), if it requires one.
    public init(host: String = "127.0.0.1", port: UInt16, decode: Bool = true, token: String? = nil) {
        connection = MessageConnection.connect(host: host, port: port)
        decodes = decode
        self.token = token
    }

    public func start() {
        connection.setHandlers(
            onReady: { [weak self] in self?.sendHello() },
            onMessage: { [weak self] message in self?.handle(message) },
            onClose: { [weak self] reason in
                self?.state.withLockUnchecked { state in
                    state.closed = true
                    state.report.closeReason = String(describing: reason)
                }
            }
        )
        connection.start()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 0.5, repeating: 1)
        timer.setEventHandler { [weak self] in self?.ping() }
        timer.resume()
        pingTimer = timer
    }

    public func stop() -> Report {
        pingTimer?.cancel()
        connection.send(.goodbye(Goodbye(reason: "user")))
        connection.close(reason: "done")
        return report
    }

    public var isClosed: Bool { state.withLockUnchecked { $0.closed } }

    /// Whether WELCOME arrived (the stream is set up).
    public var isStreaming: Bool { state.withLockUnchecked { $0.report.codec != nil } }

    /// Restarts counting (e.g. after a warm-up), keeping the stream and decoder.
    public func resetStatistics() {
        state.withLockUnchecked { state in
            let codec = state.report.codec
            let size = state.report.streamSize
            state.report = Report()
            state.report.codec = codec
            state.report.streamSize = size
            state.endToEnd.removeAll()
            state.received.removeAll()
            state.intervals.removeAll()
            state.decode.removeAll()
            state.encode.removeAll()
            state.started = .now()
        }
    }

    /// The most recent decoded picture (for snapshots).
    public var lastPicture: CVPixelBuffer? { state.withLockUnchecked { $0.snapshotBuffer } }

    public var report: Report {
        state.withLockUnchecked { state in
            var report = state.report
            let elapsed = state.started.map { (MediaTime.now() - $0).inSeconds } ?? 0
            report.seconds = elapsed
            report.framesPerSecond = elapsed > 0 ? Double(decodes ? report.framesDecoded : report.framesReceived) / elapsed : 0
            report.megabitsPerSecond = elapsed > 0 ? Double(report.bytesReceived) * 8 / elapsed / 1_000_000 : 0
            report.displayToDecodedMilliseconds = state.endToEnd.summary
            report.displayToReceivedMilliseconds = state.received.summary
            report.frameIntervalMilliseconds = state.intervals.summary
            if let median = state.intervals.percentile(0.5) {
                report.irregularIntervals = state.intervals.values.filter { $0 > median * 1.5 }.count
            }
            report.decodeMilliseconds = state.decode.summary
            report.encodeMilliseconds = state.encode.summary
            report.roundTripMicros = state.clock.best?.roundTrip
            return report
        }
    }

    private func sendHello() {
        connection.send(.hello(Hello(
            versions: VersionNegotiation.supported,
            app: .init(name: "ginga receive", version: "1"),
            device: .init(manufacturer: "apple", model: "loopback", android: "-", id: "loopback"),
            display: .init(widthPx: 2560, heightPx: 1600, densityDpi: 274, refreshRates: [60, 120], rotation: 0),
            decoders: [
                .init(mime: VideoCodec.hevc.mimeType, profiles: ["main"], maxWidth: 8192, maxHeight: 8192, maxFps: 240, lowLatency: true),
                .init(mime: VideoCodec.h264.mimeType, profiles: ["high"], maxWidth: 4096, maxHeight: 4096, maxFps: 240, lowLatency: true),
            ],
            input: nil, transport: "tcp-loopback", features: ["clock-sync"], loopbackToken: token
        )))
    }

    private func ping() {
        let id = UInt32.random(in: 0...UInt32.max)
        let t1 = MediaTime.now().nanoseconds / 1000
        state.withLockUnchecked { $0.pingSent[id] = t1 }
        connection.send(.ping(Ping(id: id, t1: t1)))
    }

    private func handle(_ message: Message) {
        switch message {
        case .welcome(let welcome):
            state.withLockUnchecked { state in
                state.report.codec = welcome.stream.codec
                state.report.streamSize = PixelSize(width: welcome.stream.width, height: welcome.stream.height)
            }
        case .streamFormat(let format):
            guard let codec = VideoCodec(rawValue: format.codec) else { return }
            let decoder = decodes ? try? VideoToolboxDecoder(codec: codec, parameterSets: format.parameterSets) : nil
            state.withLockUnchecked { state in
                state.decoder = decoder
                state.codec = codec
                state.report.streamSize = PixelSize(width: format.width, height: format.height)
            }
        case .videoFrame(let frame):
            receive(frame)
        case .pong(let pong):
            let t4 = MediaTime.now().nanoseconds / 1000
            state.withLockUnchecked { state in
                guard state.pingSent.removeValue(forKey: pong.id) != nil else { return }
                state.clock.add(t1: pong.t1, t2: pong.t2, t3: pong.t3, t4: t4)
            }
        default:
            break
        }
    }

    private func receive(_ frame: VideoFrame) {
        let arrived = MediaTime.now()
        let captureTime = MediaTime(nanoseconds: frame.captureTimeUs * 1000)
        let decoder: VideoToolboxDecoder? = state.withLockUnchecked { state in
            if state.started == nil { state.started = arrived }
            state.report.framesReceived += 1
            state.report.bytesReceived += frame.data.count
            if frame.isKeyframe { state.report.keyframes += 1 }
            state.encode.add(Double(frame.encodeDurationUs) / 1000)
            state.received.add((arrived - captureTime).inMilliseconds)
            if let last = state.lastCaptureTime, captureTime > last { state.intervals.add((captureTime - last).inMilliseconds) }
            state.lastCaptureTime = captureTime
            return state.decoder
        }
        guard let decoder else { return }
        let submitted = MediaTime.now()
        decoder.decode(frame.data) { [weak self] result in
            let decodedAt = MediaTime.now()
            self?.state.withLockUnchecked { state in
                switch result {
                case .success(let picture):
                    state.report.framesDecoded += 1
                    state.decode.add((decodedAt - submitted).inMilliseconds)
                    state.endToEnd.add((decodedAt - captureTime).inMilliseconds)
                    state.snapshotBuffer = picture.pixelBuffer
                case .failure:
                    state.report.decodeErrors += 1
                }
            }
        }
    }
}
