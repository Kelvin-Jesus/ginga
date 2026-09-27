import GingaCore
import Testing
@testable import DisplayCapture

@Suite("CaptureStatistics")
struct CaptureStatisticsTests {
    private func ms(_ value: Double) -> MediaTime { MediaTime(nanoseconds: UInt64(value * 1_000_000)) }
    private let size = PixelSize(width: 2560, height: 1600)

    private func complete(displayedAt display: Double) -> FrameMetadata {
        FrameMetadata(status: .complete, displayTime: ms(display), dirtyRectCount: 1, contentScale: 1, scaleFactor: 2)
    }

    @Test func countsFramesByStatus() {
        var statistics = CaptureStatistics()
        statistics.record(complete(displayedAt: 0), arrival: ms(4), pixelSize: size)
        statistics.record(FrameMetadata(status: .idle), arrival: ms(20), pixelSize: nil)
        statistics.record(FrameMetadata(status: .idle), arrival: ms(36), pixelSize: nil)
        statistics.record(FrameMetadata(status: .blank), arrival: ms(40), pixelSize: nil)
        let snapshot = statistics.snapshot(at: ms(50))
        #expect(snapshot.completeFrames == 1)
        #expect(snapshot.idleFrames == 2)
        #expect(snapshot.otherFrames == 1)
        #expect(snapshot.lastPixelSize == size)
    }

    @Test func measuresRateIntervalAndLatencyOfCompleteFrames() throws {
        var statistics = CaptureStatistics()
        // 60 frames, 16.667 ms apart, each delivered 3 ms after composition.
        for i in 0..<60 {
            let displayed = Double(i) * 1000 / 60
            statistics.record(complete(displayedAt: displayed), arrival: ms(displayed + 3), pixelSize: size)
        }
        let snapshot = statistics.snapshot(at: ms(995))
        #expect(snapshot.completeFrames == 60)
        #expect(snapshot.framesPerSecond == 60)
        let interval = try #require(snapshot.frameIntervalMilliseconds)
        #expect(abs(interval.mean - 16.667) < 0.01)
        #expect(interval.standardDeviation < 0.01)
        let latency = try #require(snapshot.captureLatencyMilliseconds)
        #expect(abs(latency.p50 - 3) < 0.001)
        #expect(abs(latency.max - 3) < 0.001)
    }

    @Test func rateDecaysWhenFramesStop() {
        var statistics = CaptureStatistics()
        statistics.record(complete(displayedAt: 0), arrival: ms(1), pixelSize: size)
        #expect(statistics.snapshot(at: ms(500)).framesPerSecond == 1)
        #expect(statistics.snapshot(at: ms(2_000)).framesPerSecond == 0)
    }

    @Test func resetClearsEverything() {
        var statistics = CaptureStatistics()
        statistics.record(complete(displayedAt: 0), arrival: ms(1), pixelSize: size)
        statistics.reset()
        let snapshot = statistics.snapshot(at: ms(2))
        #expect(snapshot.completeFrames == 0)
        #expect(snapshot.captureLatencyMilliseconds == nil)
        #expect(snapshot.lastPixelSize == nil)
    }

    @Test func recorderIsSafeToShareAcrossThreads() async {
        let recorder = CaptureStatisticsRecorder()
        await withTaskGroup(of: Void.self) { group in
            for task in 0..<8 {
                group.addTask {
                    for i in 0..<250 {
                        let t = Double(task * 1000 + i)
                        recorder.record(complete(displayedAt: t), arrival: ms(t + 1), pixelSize: size)
                    }
                }
            }
        }
        #expect(recorder.snapshot().completeFrames == 2000)
    }
}
