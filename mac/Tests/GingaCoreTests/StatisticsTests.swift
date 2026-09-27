import Testing
@testable import GingaCore

@Suite("SampleWindow")
struct SampleWindowTests {
    @Test func keepsOnlyTheMostRecentSamples() {
        var window = SampleWindow(capacity: 5)
        for value in 1...10 { window.add(Double(value)) }
        #expect(window.count == 5)
        #expect(window.values.sorted() == [6, 7, 8, 9, 10])
    }

    @Test func computesSummaryStatistics() throws {
        var window = SampleWindow(capacity: 5)
        for value in 6...10 { window.add(Double(value)) }
        #expect(window.mean == 8)
        #expect(window.min == 6)
        #expect(window.max == 10)
        let stddev = try #require(window.standardDeviation)
        #expect(abs(stddev - 2.0.squareRoot()) < 1e-9)
    }

    @Test func percentilesUseNearestRank() {
        var window = SampleWindow(capacity: 5)
        for value in [10.0, 6, 9, 7, 8] { window.add(value) }
        #expect(window.percentile(0) == 6)
        #expect(window.percentile(0.5) == 8)
        #expect(window.percentile(0.95) == 10)
        #expect(window.percentile(1) == 10)
    }

    @Test func emptyWindowHasNoStatistics() {
        let window = SampleWindow(capacity: 3)
        #expect(window.mean == nil)
        #expect(window.percentile(0.5) == nil)
        #expect(window.standardDeviation == nil)
        #expect(window.summary == nil)
    }

    @Test func summaryBundlesTheCommonPercentiles() throws {
        var window = SampleWindow(capacity: 100)
        for value in 1...100 { window.add(Double(value)) }
        let summary = try #require(window.summary)
        #expect(summary.p50 == 50)
        #expect(summary.p95 == 95)
        #expect(summary.p99 == 99)
        #expect(summary.max == 100)
        #expect(summary.count == 100)
    }
}

@Suite("RateMeter")
struct RateMeterTests {
    private func t(_ milliseconds: Int) -> MediaTime { MediaTime(nanoseconds: UInt64(milliseconds) * 1_000_000) }

    @Test func countsEventsInsideTheSlidingWindow() {
        var meter = RateMeter(window: .seconds(1))
        for ms in stride(from: 0, to: 1000, by: 100) { meter.record(at: t(ms)) }  // 10 events in [0, 900]
        #expect(meter.rate(at: t(950)) == 10)
        #expect(meter.rate(at: t(1_050)) == 9)  // the event at 0 ms has left the (50, 1050] window
        #expect(meter.rate(at: t(5_000)) == 0)
    }

    @Test func sumsAmountsSuchAsBytes() {
        var meter = RateMeter(window: .seconds(1))
        meter.record(at: t(0), amount: 1000)
        meter.record(at: t(500), amount: 3000)
        #expect(meter.rate(at: t(900)) == 4000)
        #expect(meter.rate(at: t(1_200)) == 3000)
        #expect(meter.rate(at: t(1_600)) == 0)
        for ms in stride(from: 2_000, to: 30_000, by: 1) { meter.record(at: t(ms), amount: 2) }  // compaction
        #expect(meter.rate(at: t(29_999)) == 2000)
    }

    @Test func scalesToEventsPerSecondForShortWindows() {
        var meter = RateMeter(window: .milliseconds(500))
        for ms in stride(from: 0, to: 500, by: 10) { meter.record(at: t(ms)) }  // 50 events in 0.5 s
        #expect(meter.rate(at: t(495)) == 100)
    }
}
