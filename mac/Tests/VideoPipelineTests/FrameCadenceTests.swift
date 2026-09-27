import GingaCore
import Testing
@testable import VideoPipeline

@Suite("FrameCadence")
struct FrameCadenceTests {
    /// Feeds frames at the given capture times (milliseconds) and returns the ones taken.
    func run(_ cadence: inout FrameCadence, _ times: [Double]) -> [Double] {
        times.filter { ms in
            let time = MediaTime(nanoseconds: 1_000_000_000 + UInt64(ms * 1_000_000))
            guard cadence.admits(time) else { return false }
            cadence.take(time)
            return true
        }
    }

    func grid(hz: Double, seconds: Double = 1, jitter: (Int) -> Double = { _ in 0 }) -> [Double] {
        (0..<Int(hz * seconds)).map { Double($0) * 1000 / hz + jitter($0) }
    }

    @Test func halvesA120HzSourceExactly() {
        var cadence = FrameCadence(frameRate: 60)
        let taken = run(&cadence, grid(hz: 120))
        #expect(taken.count == 60)
        #expect(zip(taken, taken.dropFirst()).allSatisfy { abs($1 - $0 - 1000.0 / 60) < 0.01 })
    }

    @Test func passesASourceAtTheRateDespiteJitter() {
        var cadence = FrameCadence(frameRate: 60)
        // ±1.5 ms of timestamp jitter around a 60 Hz grid.
        let source = grid(hz: 60) { $0 % 2 == 0 ? 1.5 : -1.5 }
        #expect(run(&cadence, source).count == source.count)
    }

    @Test func averagesTheRateFromAnyFasterSource() {
        var cadence = FrameCadence(frameRate: 60)
        let taken = run(&cadence, grid(hz: 144, seconds: 2))
        #expect((119...121).contains(taken.count))
    }

    @Test func neverSendsBurstsAfterAGap() {
        var cadence = FrameCadence(frameRate: 60)
        // 60 Hz content landing on a 120 Hz grid with an irregular phase.
        let source: [Double] = [0, 25, 33.3, 41.7, 58.3, 66.7, 75, 100, 108.3]
        let taken = run(&cadence, source)
        let spacings = zip(taken, taken.dropFirst()).map { $1 - $0 }
        #expect(spacings.allSatisfy { $0 >= 1000.0 / 60 - 4 })
        #expect(taken.first == 0)
    }

    @Test func aRefusedFrameLeavesTheSlotOpen() {
        var cadence = FrameCadence(frameRate: 60)
        let t0 = MediaTime(nanoseconds: 1_000_000_000)
        cadence.take(t0)
        let t1 = t0.advanced(by: .milliseconds(17))
        #expect(cadence.admits(t1))
        // Not taken (e.g. backpressure): the next frame is still due.
        let t2 = t0.advanced(by: .milliseconds(25))
        #expect(cadence.admits(t2))
    }

    @Test func uncappedHighRatesPassEverything() {
        var cadence = FrameCadence(frameRate: 120)
        #expect(run(&cadence, grid(hz: 120)).count == 120)
    }

    /// Streaming at the display's own rate there is nothing to cap: timestamp jitter, or a late
    /// frame that re-anchors the schedule, must never cost a frame (120 Hz stability).
    @Test func aSourceNoFasterThanTheRatePassesWhateverItsTiming() {
        var cadence = FrameCadence(frameRate: 120, sourceRate: 120)
        #expect(cadence.isPassthrough)
        // A late frame (+3 ms) followed by one back on the grid: without passthrough the second
        // one is 3 ms early for the re-anchored slot and would be dropped.
        let source = grid(hz: 120) { $0 % 10 == 5 ? 3 : 0 }
        #expect(run(&cadence, source).count == source.count)

        var unknownSource = FrameCadence(frameRate: 120)
        #expect(run(&unknownSource, source).count < source.count)
    }

    @Test func passthroughFollowsTheSourceRate() {
        var cadence = FrameCadence(frameRate: 60, sourceRate: 60)
        #expect(cadence.isPassthrough)
        cadence.sourceRate = 120  // e.g. the display switched back to 120 Hz on the power adapter
        #expect(!cadence.isPassthrough)
        #expect(run(&cadence, grid(hz: 120)).count == 60)
        cadence.frameRate = 120
        #expect(cadence.isPassthrough)
    }
}
