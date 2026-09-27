import GingaCore
import Testing
@testable import VideoPipeline

@Suite("BitrateController")
struct BitrateControllerTests {
    let t0 = MediaTime(nanoseconds: 1_000_000_000)

    func sample(_ ms: Int, latency: Double?, dropped: Int = 0, skipped: Int = 0) -> BitrateController.Sample {
        BitrateController.Sample(time: t0.advanced(by: .milliseconds(Int64(ms))), endToEndP50Milliseconds: latency, framesDropped: dropped, framesSkippedForBackpressure: skipped)
    }

    @Test func probesUpwardOnAStableLink() {
        var controller = BitrateController(limits: .init(minimumKbps: 2_000, startKbps: 10_000, maximumKbps: 30_000))
        for step in 0..<20 { _ = controller.update(sample(step * 250, latency: 20)) }
        #expect(controller.targetKbps > 10_000)
        #expect(controller.targetKbps <= 30_000)
        for step in 20..<400 { _ = controller.update(sample(step * 250, latency: 20)) }
        #expect(controller.targetKbps == 30_000)  // never above the maximum
    }

    /// Queueing delay (latency rising above its floor) is the early signal, before any loss.
    @Test func backsOffWhenLatencyRisesAboveItsFloor() {
        var controller = BitrateController(limits: .init(startKbps: 20_000))
        for step in 0..<8 { _ = controller.update(sample(step * 250, latency: 20)) }
        let before = controller.targetKbps
        let changed = controller.update(sample(2_000, latency: 70))
        #expect(changed == Int(Double(before) * 0.7))
        #expect(controller.latencyFloorMilliseconds == 20)
    }

    @Test func backsOffOnBackpressureAndDrops() {
        var skipped = BitrateController(limits: .init(startKbps: 20_000))
        #expect(skipped.update(sample(0, latency: nil, skipped: 3)) == 14_000)
        var dropped = BitrateController(limits: .init(startKbps: 20_000))
        #expect(dropped.update(sample(0, latency: 20, dropped: 1)) == 14_000)
    }

    /// Several reports describe the same queue: one decrease per half hold period, and no
    /// increase until the queue had time to drain.
    @Test func oneDecreasePerCongestionEpisodeThenHold() {
        var controller = BitrateController(limits: .init(startKbps: 20_000))
        #expect(controller.update(sample(0, latency: nil, skipped: 1)) == 14_000)
        #expect(controller.update(sample(250, latency: nil, skipped: 1)) == nil)
        #expect(controller.update(sample(500, latency: nil)) == nil)  // held
        #expect(controller.update(sample(1_500, latency: nil)) == nil)  // still held
        #expect(controller.update(sample(2_000, latency: nil)) != nil)  // probing again
    }

    @Test func neverBelowTheMinimum() {
        var controller = BitrateController(limits: .init(minimumKbps: 2_000, startKbps: 3_000, maximumKbps: 30_000))
        for step in 0..<50 { _ = controller.update(sample(step * 1_000, latency: nil, dropped: 5)) }
        #expect(controller.targetKbps == 2_000)
    }
}
