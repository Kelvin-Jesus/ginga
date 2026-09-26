import AppKit
import DisplayCapture
import EnergyMeter
import Foundation
import Tab2MacCore
import Tab2MacSession
import Tab2MacSecurity
import Tab2MacStreaming

/// Measures what each streaming configuration costs in energy: it launches the app per scenario
/// (capture needs the app's Screen Recording grant), receives on this Mac, and reads SoC energy
/// (IOReport) plus per-process CPU, energy and wake-ups over a steady-state window.
@MainActor
enum PowerBenchmark {
    struct Scenario: Sendable {
        var name: String
        /// nil measures the system without Tab2Mac (baseline).
        var configuration: Tab2MacConfiguration?
        var appArguments: [String] = []
        var receives = false
    }

    struct Measurement: Codable, Sendable {
        var scenario: String
        var run: Int
        var seconds: Double
        var soc: EnergyBreakdown?
        var processes: [String: ProcessRates]
        var stream: Stream?
    }

    struct Stream: Codable, Sendable {
        var framesPerSecond: Double
        var megabitsPerSecond: Double
        var frameIntervalMilliseconds: StatisticSummary?
        var displayToReceivedMilliseconds: StatisticSummary?
        var displayToDecodedMilliseconds: StatisticSummary?
        var encodeMilliseconds: StatisticSummary?
    }

    struct Summary: Codable, Sendable {
        var scenario: String
        var runs: Int
        var soc: EnergyBreakdown?
        /// `soc` minus the mean baseline.
        var socAboveBaseline: EnergyBreakdown?
        var processes: [String: ProcessRates]
        var framesPerSecond: Double?
        var frameIntervalP95Milliseconds: Double?
        var megabitsPerSecond: Double?
    }

    static let baselineName = "baseline (no Tab2Mac)"

    /// The default matrix. Every streaming scenario shows the test pattern (Core Animation moving
    /// every vsync plus a clock), i.e. continuous change: the worst case for power.
    static func scenarios(basePort: UInt16) -> [Scenario] {
        func configuration(refresh: Double, streamFPS: Double?, decimation: FrameDecimation = .captureService,
                           pixelFormat: CapturePixelFormat = .yuv420VideoRange, port: UInt16) -> Tab2MacConfiguration {
            var configuration = Tab2MacConfiguration()
            configuration.display.refreshRate = refresh
            configuration.capture.maxFrameRate = streamFPS
            configuration.capture.decimation = decimation
            configuration.capture.pixelFormat = pixelFormat
            configuration.streaming.port = port
            configuration.streaming.adbAutoReverse = false
            return configuration
        }
        // --background: menu bar only, as in daily use (the control panel costs CPU while open).
        let stream = ["--background", "--serve", "--test-pattern"]
        return [
            Scenario(name: baselineName),
            Scenario(name: "compose only, 120 Hz", configuration: configuration(refresh: 120, streamFPS: 60, port: basePort),
                     appArguments: ["--background", "--create-display", "--test-pattern"]),
            Scenario(name: "compose only, 60 Hz", configuration: configuration(refresh: 60, streamFPS: 60, port: basePort + 1),
                     appArguments: ["--background", "--create-display", "--test-pattern"]),
            Scenario(name: "static desktop, 60 Hz", configuration: configuration(refresh: 60, streamFPS: 60, port: basePort + 2),
                     appArguments: ["--background", "--serve"], receives: true),
            Scenario(name: "120 Hz → 60 fps (SCK drops)", configuration: configuration(refresh: 120, streamFPS: 60, port: basePort + 3),
                     appArguments: stream, receives: true),
            Scenario(name: "120 Hz → 60 fps (in-process)", configuration: configuration(refresh: 120, streamFPS: 60, decimation: .inProcess, port: basePort + 4),
                     appArguments: stream, receives: true),
            Scenario(name: "60 Hz → 60 fps", configuration: configuration(refresh: 60, streamFPS: 60, port: basePort + 5),
                     appArguments: stream, receives: true),
            Scenario(name: "120 Hz → 120 fps", configuration: configuration(refresh: 120, streamFPS: nil, port: basePort + 6),
                     appArguments: stream, receives: true),
            Scenario(name: "60 Hz → 60 fps, BGRA capture", configuration: configuration(refresh: 60, streamFPS: 60, pixelFormat: .bgra, port: basePort + 7),
                     appArguments: stream, receives: true),
        ]
    }

    static func run(
        scenarios: [Scenario], app: URL, warmup: Duration, window: Duration, repeats: Int, decode: Bool,
        log: (String) -> Void
    ) async -> [Measurement] {
        let meter: SoCEnergyMeter?
        do {
            meter = try SoCEnergyMeter()
        } catch {
            log("SoC energy unavailable (\(error)); reporting process figures only")
            meter = nil
        }
        var measurements: [Measurement] = []
        // Interleave repeats (A B C … A B C …) so slow drift in background load spreads evenly.
        for run in 1...max(1, repeats) {
            for scenario in scenarios {
                do {
                    let measurement = try await measure(scenario, run: run, app: app, warmup: warmup, window: window, decode: decode, meter: meter)
                    measurements.append(measurement)
                    log(describe(measurement))
                } catch {
                    log("\(scenario.name) #\(run): failed — \(error)")
                }
            }
        }
        return measurements
    }

    private static func measure(
        _ scenario: Scenario, run: Int, app: URL, warmup: Duration, window: Duration, decode: Bool, meter: SoCEnergyMeter?
    ) async throws -> Measurement {
        var instance: NSRunningApplication?
        var receiver: LoopbackReceiver?
        func tearDown() async {
            _ = receiver?.stop()
            if let instance { await quit(instance) }
            // Let WindowServer settle after the display goes away.
            try? await Task.sleep(for: .seconds(instance == nil ? 0 : 3))
        }
        do {
            if let configuration = scenario.configuration {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("t2m-power-\(configuration.streaming.port).json")
                try JSONEncoder().encode(configuration).write(to: file)
                let token = LoopbackToken.generate()
                instance = try await launch(app: app, arguments: ["--config", file.path, "--loopback-token", token] + scenario.appArguments)
                if scenario.receives {
                    receiver = try await connect(port: configuration.streaming.port, decode: decode, token: token, timeout: .seconds(25))
                }
            }
            try await Task.sleep(for: warmup)
            receiver?.resetStatistics()

            var pids: [String: pid_t] = ["t2m (receiver)": getpid()]
            for name in ["WindowServer", "replayd"] { if let pid = ProcessUsage.pids(named: name).first { pids[name] = pid } }
            if let instance { pids["Tab2Mac"] = instance.processIdentifier }
            let startEnergy = meter?.read()
            let startUsage = pids.compactMapValues { ProcessUsage.read(pid: $0) }
            let started = MediaTime.now()
            try await Task.sleep(for: window)
            let endEnergy = meter?.read()
            let endUsage = pids.compactMapValues { ProcessUsage.read(pid: $0) }
            let seconds = (MediaTime.now() - started).inSeconds
            let report = receiver?.report

            var processes: [String: ProcessRates] = [:]
            for (name, start) in startUsage {
                if let end = endUsage[name] { processes[name] = ProcessRates(from: start, to: end, seconds: seconds) }
            }
            var soc: EnergyBreakdown?
            if let meter, let startEnergy, let endEnergy {
                soc = EnergyBreakdown(channels: meter.channels(from: startEnergy, to: endEnergy), seconds: (endEnergy.time - startEnergy.time).inSeconds)
            }
            let stream = report.map {
                Stream(
                    framesPerSecond: $0.framesPerSecond, megabitsPerSecond: $0.megabitsPerSecond,
                    frameIntervalMilliseconds: $0.frameIntervalMilliseconds, displayToReceivedMilliseconds: $0.displayToReceivedMilliseconds,
                    displayToDecodedMilliseconds: $0.displayToDecodedMilliseconds, encodeMilliseconds: $0.encodeMilliseconds
                )
            }
            await tearDown()
            return Measurement(scenario: scenario.name, run: run, seconds: seconds, soc: soc, processes: processes, stream: stream)
        } catch {
            await tearDown()
            throw error
        }
    }

    private static func launch(app: URL, arguments: [String]) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.arguments = arguments
        return try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }

    private static func quit(_ instance: NSRunningApplication) async {
        instance.terminate()
        for _ in 0..<60 where !instance.isTerminated {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !instance.isTerminated { instance.forceTerminate() }
    }

    /// The app needs a moment to create the display and listen; retry until the stream is set up.
    private static func connect(port: UInt16, decode: Bool, token: String, timeout: Duration) async throws -> LoopbackReceiver {
        let deadline = MediaTime.now().advanced(by: timeout)
        while MediaTime.now() < deadline {
            let receiver = LoopbackReceiver(port: port, decode: decode, token: token)
            receiver.start()
            let attemptEnds = MediaTime.now().advanced(by: .seconds(2))
            while MediaTime.now() < attemptEnds, !receiver.isClosed {
                if receiver.isStreaming { return receiver }
                try await Task.sleep(for: .milliseconds(100))
            }
            _ = receiver.stop()
            try await Task.sleep(for: .milliseconds(500))
        }
        throw CLIError.failed("no stream on 127.0.0.1:\(port) within \(timeout)")
    }

    // MARK: Reporting

    static func summarize(_ measurements: [Measurement]) -> [Summary] {
        let baseline = EnergyBreakdown.mean(measurements.filter { $0.scenario == baselineName }.compactMap(\.soc))
        var order: [String] = []
        for measurement in measurements where !order.contains(measurement.scenario) { order.append(measurement.scenario) }
        return order.map { name in
            let runs = measurements.filter { $0.scenario == name }
            let soc = EnergyBreakdown.mean(runs.compactMap(\.soc))
            var processes: [String: ProcessRates] = [:]
            for process in Set(runs.flatMap { $0.processes.keys }) {
                let rates = runs.compactMap { $0.processes[process] }
                processes[process] = ProcessRates(
                    cpuPercent: mean(rates.map(\.cpuPercent)) ?? 0,
                    milliwatts: mean(rates.compactMap(\.milliwatts)),
                    wakeupsPerSecond: mean(rates.compactMap(\.wakeupsPerSecond))
                )
            }
            let streams = runs.compactMap(\.stream)
            return Summary(
                scenario: name, runs: runs.count, soc: soc,
                socAboveBaseline: name == baselineName ? nil : pair(soc, baseline).map { $0.0 - $0.1 },
                processes: processes,
                framesPerSecond: mean(streams.map(\.framesPerSecond)),
                frameIntervalP95Milliseconds: mean(streams.compactMap { $0.frameIntervalMilliseconds?.p95 }),
                megabitsPerSecond: mean(streams.map(\.megabitsPerSecond))
            )
        }
    }

    static func describe(_ m: Measurement) -> String {
        var parts = ["\(m.scenario) #\(m.run):"]
        if let stream = m.stream {
            parts.append(String(format: "%.1f fps", stream.framesPerSecond))
            if let interval = stream.frameIntervalMilliseconds {
                parts.append(String(format: "interval p50 %.1f p95 %.1f ms", interval.p50, interval.p95))
            }
            parts.append(String(format: "%.1f Mbit/s", stream.megabitsPerSecond))
        }
        if let soc = m.soc {
            parts.append(String(format: "SoC %.0f mW (cpu %.0f gpu %.0f ave %.0f mem %.0f)", soc.total, soc.cpu, soc.gpu, soc.encoder, soc.memory))
        }
        for name in m.processes.keys.sorted() {
            guard let rates = m.processes[name] else { continue }
            var text = String(format: "%@ %.1f%%", name, rates.cpuPercent)
            if let milliwatts = rates.milliwatts { text += String(format: " %.0f mW", milliwatts) }
            if let wakeups = rates.wakeupsPerSecond { text += String(format: " %.0f wk/s", wakeups) }
            parts.append(text)
        }
        return parts.joined(separator: " · ")
    }

    static func markdownTable(_ summaries: [Summary]) -> String {
        func number(_ value: Double?, _ format: String = "%.0f") -> String { value.map { String(format: format, $0) } ?? "–" }
        var lines = [
            "| Scenario | Stream fps | Interval p95 (ms) | Mbit/s | SoC (mW) | Δ SoC vs baseline | Δ CPU | Δ GPU | Encoder (AVE) | Δ Memory | Tab2Mac CPU % / mW / wake-ups/s | WindowServer CPU % | replayd CPU % / mW |",
            "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
        ]
        for s in summaries {
            let app = s.processes["Tab2Mac"].map { "\(number($0.cpuPercent, "%.1f")) / \(number($0.milliwatts)) / \(number($0.wakeupsPerSecond))" } ?? "–"
            let replayd = s.processes["replayd"].map { "\(number($0.cpuPercent, "%.1f")) / \(number($0.milliwatts))" } ?? "–"
            let delta = s.socAboveBaseline
            lines.append("| \(s.scenario) (\(s.runs)×) | \(number(s.framesPerSecond, "%.1f")) | \(number(s.frameIntervalP95Milliseconds, "%.1f")) | \(number(s.megabitsPerSecond, "%.1f")) | \(number(s.soc?.total)) | \(number(delta?.total, "%+.0f")) | \(number(delta?.cpu, "%+.0f")) | \(number(delta?.gpu, "%+.0f")) | \(number(s.soc?.encoder)) | \(number(delta?.memory, "%+.0f")) | \(app) | \(number(s.processes["WindowServer"]?.cpuPercent, "%.1f")) | \(replayd) |")
        }
        return lines.joined(separator: "\n")
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

private func pair(_ a: EnergyBreakdown?, _ b: EnergyBreakdown?) -> (EnergyBreakdown, EnergyBreakdown)? {
    guard let a, let b else { return nil }
    return (a, b)
}
