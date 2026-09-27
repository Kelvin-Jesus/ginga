import Darwin
import Foundation
import GingaCore
import Testing
@testable import EnergyMeter

@Suite("EnergyBreakdown")
struct EnergyBreakdownTests {
    @Test func aggregateChannelsAreCountedOnceAndPartsAreSkipped() {
        // Channel names and units as IOReport reports them on an M4 (per-core and DTL channels are
        // parts of "CPU Energy"; "GPU" duplicates "GPU Energy").
        let channels: [SoCEnergyMeter.Channel] = [
            .init(name: "ECPU0", joules: 0.293), .init(name: "PCPU3", joules: 2.116), .init(name: "ECPM", joules: 0.445),
            .init(name: "ECPU", joules: 1.793), .init(name: "PCPU", joules: 8.294), .init(name: "PCPUDTL04", joules: 2.020),
            .init(name: "CPU Energy", joules: 10.087),
            .init(name: "GPU", joules: 0.007), .init(name: "GPU SRAM", joules: 0.001), .init(name: "GPU Energy", joules: 0.00728),
            .init(name: "AVE", joules: 0.2), .init(name: "VDEC", joules: 0.004), .init(name: "MSR", joules: 0.058),
            .init(name: "DRAM", joules: 1.4), .init(name: "AMCC", joules: 0.9), .init(name: "DCS", joules: 1.24),
            .init(name: "DISP", joules: 0.016), .init(name: "DISPEXT", joules: 0.294),
            .init(name: "ISP", joules: 0.022), .init(name: "SOC_AON", joules: 0.002),
        ]
        let breakdown = EnergyBreakdown(channels: channels, seconds: 2)
        #expect(abs(breakdown.cpu - 5043.5) < 0.01)
        #expect(abs(breakdown.gpu - 4.14) < 0.01)
        #expect(abs(breakdown.encoder - 100) < 0.01)
        #expect(abs(breakdown.decoder - 2) < 0.01)
        #expect(abs(breakdown.scaler - 29) < 0.01)
        #expect(abs(breakdown.memory - 1770) < 0.01)
        #expect(abs(breakdown.display - 155) < 0.01)
        #expect(abs(breakdown.other - 12) < 0.01)
        #expect(abs(breakdown.total - (5043.5 + 4.14 + 100 + 2 + 29 + 1770 + 155 + 12)) < 0.01)
    }

    @Test func differenceAndMeanAreElementWise() throws {
        var a = EnergyBreakdown(seconds: 10)
        a.cpu = 300; a.encoder = 80; a.total = 380
        var b = EnergyBreakdown(seconds: 10)
        b.cpu = 100; b.total = 100
        let delta = a - b
        #expect(delta.cpu == 200 && delta.encoder == 80 && delta.total == 280)
        let mean = try #require(EnergyBreakdown.mean([a, b]))
        #expect(mean.cpu == 200 && mean.encoder == 40 && mean.total == 240)
        #expect(EnergyBreakdown.mean([]) == nil)
    }

    @Test func unitLabelsScaleToJoules() {
        #expect(SoCEnergyMeter.joulesPerUnit("mJ") == 1e-3)
        #expect(SoCEnergyMeter.joulesPerUnit("nJ") == 1e-9)
        #expect(SoCEnergyMeter.joulesPerUnit("uJ") == 1e-6)
        #expect(SoCEnergyMeter.joulesPerUnit("mW") == nil)
        #expect(SoCEnergyMeter.joulesPerUnit(nil) == nil)
    }

    /// Reading IOReport must either work or fail with a typed error, never crash.
    @Test func ioReportIsReadableOrReportsWhyNot() async throws {
        do {
            let meter = try SoCEnergyMeter()
            let start = try #require(meter.read())
            try await Task.sleep(for: .milliseconds(200))
            let end = try #require(meter.read())
            let channels = meter.channels(from: start, to: end)
            #expect(channels.contains { $0.name == "CPU Energy" })
            #expect(EnergyBreakdown(channels: channels, seconds: (end.time - start.time).inSeconds).cpu > 0)
        } catch let error as SoCEnergyMeter.Unavailable {
            // Other Macs may lack the channels; the tool then reports this instead of energy.
            #expect(!error.description.isEmpty)
        }
    }
}

@Suite("ProcessUsage")
struct ProcessUsageTests {
    @Test func psTimeFormatsParse() {
        #expect(ProcessUsage.parseCPUTime("0:05.69") == 5.69)
        #expect(ProcessUsage.parseCPUTime("1168:33.64\n") == 1168 * 60 + 33.64)
        #expect(ProcessUsage.parseCPUTime("1:02:03.50") == 3723.5)
        #expect(ProcessUsage.parseCPUTime("") == nil)
        #expect(ProcessUsage.parseCPUTime("abc") == nil)
    }

    @Test func ownProcessReportsCPUEnergyAndWakeups() throws {
        let usage = try #require(ProcessUsage.read(pid: getpid()))
        #expect(usage.cpuSeconds > 0)
        #expect(usage.energyJoules != nil)
        #expect(usage.wakeups != nil)
    }

    @Test func otherUsersProcessesFallBackToCPUTime() throws {
        // WindowServer runs as _windowserver: libproc refuses, `ps` still reports CPU time.
        let pid = try #require(ProcessUsage.pids(named: "WindowServer").first)
        let usage = try #require(ProcessUsage.read(pid: pid))
        #expect(usage.cpuSeconds > 0)
        #expect(usage.energyJoules == nil)
    }

    @Test func ratesOverAWindow() {
        let rates = ProcessRates(
            from: ProcessUsage(cpuSeconds: 10, energyJoules: 5, wakeups: 100),
            to: ProcessUsage(cpuSeconds: 10.5, energyJoules: 6, wakeups: 300),
            seconds: 10
        )
        #expect(rates.cpuPercent == 5)
        #expect(rates.milliwatts == 100)
        #expect(rates.wakeupsPerSecond == 20)
        #expect(ProcessRates(from: ProcessUsage(cpuSeconds: 1), to: ProcessUsage(cpuSeconds: 2), seconds: 10).milliwatts == nil)
    }
}
