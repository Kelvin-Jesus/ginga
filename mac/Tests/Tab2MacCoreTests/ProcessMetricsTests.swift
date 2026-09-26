import Testing
@testable import Tab2MacCore

@Suite("ProcessMetrics")
struct ProcessMetricsTests {
    @Test func memoryFootprintIsReported() throws {
        let bytes = try #require(ProcessMetrics.memoryFootprintBytes())
        #expect(bytes > 1_000_000)
    }

    @Test func cpuSamplerSeesBusyWork() {
        var sampler = CPUUsageSampler()
        _ = sampler.sample()
        let deadline = MediaTime.now().advanced(by: .milliseconds(60))
        var accumulator = 0.0
        while MediaTime.now() < deadline { accumulator += 1.0.squareRoot() }
        #expect(accumulator > 0)
        let percent = sampler.sample()
        #expect(percent > 10)
    }

    @Test func gpuUtilizationIsAPercentageWhenAvailable() {
        guard let utilization = GPUUtilization.read() else { return }  // not available on all hosts
        #expect((0...100).contains(utilization.devicePercent))
    }
}
